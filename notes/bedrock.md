# Bedrock backend

I would like to allow an Amazon Bedrock model to act as the teacher while the student continues to run on a local Ollama backend.

## Approach

Add a `bedrock` adapter behind `Inference::Client.for`, using the official AWS SDK for Ruby and the non-streaming Converse API. Keep AWS-specific request translation inside the adapter rather than adding a separate refinement implementation.

The teacher has two responsibilities: generate a reference response for every test case, once per refinement, and evaluate the student responses and propose a new prompt on each iteration. The first goes through `TrialExecutionJob#complete`; the second goes through `RefinementJob#generate` with `RefinementEvaluation::FORMAT`. Both paths must work before Bedrock is usable as a teacher.

[Converse](https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_Converse.html) provides a common messages interface for supported Bedrock models and accepts a foundation-model identifier or inference-profile identifier. It requires `bedrock:InvokeModel` permission. Use it instead of implementing each model provider's native request format.

## Backend configuration and history

- Add `bedrock` to `Backend::ADAPTERS` and extend the `backends_adapter_check` database constraint in a migration. Keep the required system Ollama backend unchanged.
- Configure the Bedrock region through the deployment’s `AWS_REGION`, alongside credentials. Do not add region columns to backends, trials, or refinements. Do not hard-code a model or assume it is available in every region.
- For Bedrock, hide the editable base URL and derive the runtime endpoint through AWS endpoint resolution. The existing non-null `base_url` can hold the resolved runtime URL for display and compatibility; do not treat an Ollama URL as a Bedrock endpoint. Initially support standard AWS endpoints, with custom endpoints deferred.
- Extend the settings forms and permitted parameters to select the adapter and display the deployment region on the backend list. Do not accept a region form parameter. Apply URL validation according to the adapter.
- Snapshot adapter on trials and on both refinement roles, alongside the existing backend name and URL snapshots. Backfill existing snapshots as `ollama`. Pass this saved configuration into the client factory during execution. Keep credentials out of snapshots.

This needs an explicit configuration object or extra factory keywords: today `Inference::Client.for(backend, base_url:)` snapshots only the URL. Reading the adapter from the current backend would let later edits change the meaning of a queued or historical run. Region and credentials are deployment configuration: changing AWS_REGION affects future Bedrock requests, including queued work; existing URL snapshots remain historical records. Make adapter changes on an existing backend invalid, since its model catalog belongs to that adapter; create another backend to switch providers.

There is also an existing refinement snapshot gap to address: reference and student trials are created from the current backend record, and teacher evaluation constructs its client from that record. Ensure those paths use the refinement's saved configuration, rather than taking fresh settings after every iteration.

## AWS credentials and permissions

Use the SDK's [credential provider chain](https://docs.aws.amazon.com/sdk-for-ruby/v3/developer-guide/credential-providers.html), with short-lived credentials where possible. Do not add AWS secret fields to the backend form for the first version. Support one deployment identity; multiple AWS accounts and per-backend role assumption can follow later.

Both Compose services, `app` and `jobs`, need the same credential setup. For temporary environment credentials, explicitly pass `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, and `AWS_SESSION_TOKEN` to both. Alternatively, mount the required shared configuration and credential/cache files at the container user's AWS paths and pass `AWS_PROFILE`. A profile configured on the host is not automatically available inside Docker. Document the chosen login and refresh procedure; do not bake credentials into the image or commit them to the repository.

Grant invocation access only to the intended models/profiles. Discovery also needs `bedrock:ListFoundationModels` and, if enabled, `bedrock:ListInferenceProfiles`. Confirm provider-specific account prerequisites and model access in the chosen region. Listing a model does not prove that the account can invoke it.

For inference profiles, follow AWS's [profile permission requirements](https://docs.aws.amazon.com/bedrock/latest/userguide/inference-profiles-prereq.html): authorization must cover the profile and applicable underlying model resources. Account policies and regional restrictions can prevent cross-region routing. Choose geographic routing deliberately rather than silently selecting a global profile.

## Client wrapper

Add `aws-sdk-bedrockruntime` and `aws-sdk-bedrock` through Bundler in Docker. Implement `Inference::BedrockClient` under `app/services/inference/bedrock_client.rb`, keeping it separate from the SDK's `Aws` namespace. Inject SDK clients for tests.

Match the existing application interface:

```ruby
models # array of { "name" => invocation_id, "size" => nil, "details" => {...} }
generate(model:, prompt:, format: nil, options: nil) # text String
complete(model:, prompt:, format: nil, options: nil) # content and metrics
```

Have `generate` delegate to `complete(...).content`. Consider extracting a shared `Inference::Completion` value object instead of making the new adapter depend on `Ollama::Client::Completion`.

The core request is a single user message. For example, inside the wrapper:

```ruby
request = {
  model_id: model,
  messages: [{ role: "user", content: [{ text: prompt }] }],
  inference_config: { max_tokens: output_limit }
}

if format
  request[:output_config] = {
    text_format: {
      type: "json_schema",
      structure: {
        json_schema: {
          name: "refinement_evaluation",
          schema: JSON.generate(format)
        }
      }
    }
  }
end

reply = runtime.converse(**request)
```

This is a request sketch, not a complete adapter. The Ruby SDK uses `output_config.text_format` and a `structure.json_schema` member; see [OutputConfig](https://docs.aws.amazon.com/sdk-for-ruby/v3/api/Aws/BedrockRuntime/Types/OutputConfig.html) and [OutputFormatStructure](https://docs.aws.amazon.com/sdk-for-ruby/v3/api/Aws/BedrockRuntime/Types/OutputFormatStructure.html). Pin SDK versions that include these fields.

Translate options deliberately. `num_ctx` is Ollama-specific and must not be sent to Bedrock. Relabel the refinement's context-size field as Ollama-only or hide it when Bedrock is selected. Send temperature only where the selected model supports it. Add a configurable output-token limit with a model-compatible default; evaluation replies contain all case notes and the complete proposed prompt, so a small chat-response limit is insufficient. Do not silently retry a rejected parameter by removing arbitrary settings.

Read text blocks from the assistant message, preserving their order. Exclude reasoning and other non-text blocks. Validate the stop reason and treat truncation, guardrail intervention, refusal, unexpected tool use, or an empty text response as actionable errors instead of saving a successful response. Keep provider-specific behavior covered by adapter tests.

## Structured evaluation output

Start with a small, explicit set of teacher models supporting both Converse and native JSON-schema output. AWS documents supported models, schema restrictions, and examples in [structured outputs](https://docs.aws.amazon.com/bedrock/latest/userguide/structured-output.html). Support varies by model; plain text generation capability alone is insufficient.

Use `RefinementEvaluation::FORMAT` as the schema, adding `additionalProperties: false` to its object definitions where required by the supported schema subset. Keep `RefinementEvaluation#parse` and its existing one-retry policy: schema compliance does not establish that the response covers the right cases or that its proposed prompt uses valid variables.

Fail clearly for unsupported teacher configurations. A forced-tool fallback is a possible later extension, but should not be silently substituted for native structured output in the initial version. Account for first-use schema compilation when choosing request timeouts; AWS notes that compilation can take approximately 90 seconds.

## Model discovery and connection checks

Implement discovery with `Aws::Bedrock::Client`, separately from the runtime client. Use [ListFoundationModels and ListInferenceProfiles](https://docs.aws.amazon.com/bedrock/latest/userguide/models-get-info.html), paginating profile results. Return only supported text-generation candidates, excluding embeddings and image-only models. Keep a capability allowlist for the initial teacher models; discovery metadata alone does not prove structured-output compatibility.

Some models must be invoked through a profile rather than their foundation-model ID. Store the exact usable ID or ARN as `LanguageModel.name`, because that value is copied into trials and refinements and passed back for inference. Preserve a readable display name and provider metadata in `details`; avoid deriving the family from an ARN. AWS explains [using profiles for invocation](https://docs.aws.amazon.com/bedrock/latest/userguide/inference-profiles-use.html).

Allow a configured list of invocation IDs/ARNs as an alternative to broad discovery, particularly for application inference profiles and restricted IAM identities. If a discovery request fails, leave that backend's existing model availability unchanged, as `Inference::ModelCatalog` does today. Do not interpret a partial discovery result as a complete catalog and mark valid models unavailable.

The existing **Test connection** action lists models. For Bedrock, describe this as a credential/discovery check; it is not proof of invocation access. If an inference test is added, make it a separate explicit action showing that it sends a paid request.

## Errors, metrics, and refinement behavior

Introduce a common `Inference::Error`, make the Ollama error inherit from it, and wrap AWS SDK service, credential, and transport errors in a Bedrock subclass. Update rescues in `TrialExecutionJob`, `RefinementJob`, the catalog, settings connection checks, and other generation controllers. Otherwise an AWS failure can escape per-response handling and leave response records pending even though the trial is failed.

Keep messages useful for access denial, expired credentials, missing regional model access, throttling, invalid parameters, and timeouts. Redact credentials and avoid logging full teacher requests by default. Use bounded SDK retries and timeouts; do not add unlimited job retries that repeatedly incur inference charges.

Map Converse's input/output token usage to the existing `prompt_eval_count` and `eval_count` response fields. Measure elapsed wall time with a monotonic clock and store nanoseconds in `total_duration`. Leave Ollama-only load/evaluation timings unset; do not fabricate generation throughput. See the [Converse response fields](https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_Converse.html).

Teacher evaluation currently saves only request and response text on the iteration, so exposing its usage requires iteration metrics fields and a way to retrieve completion metrics from `RefinementJob`. This can follow basic support, but reference-trial tokens alone must not be presented as the teacher's total cost.

Preserve the existing reference reuse and iteration chaining. **Run to completion** should stop at the target agreement, teacher completion signal, or iteration limit, and pause on a Bedrock failure. Show the backend and region in teacher selection and explain that the teacher receives test cases plus reference and student outputs. Bedrock selection will also make the backend available to other generation flows unless the application introduces role restrictions; ensure these paths handle the adapter consistently.

## Implementation and verification sequence

1. Introduce common inference errors and a shared completion type; verify Ollama behavior remains intact.
2. Add the adapter constraint migration, environment region configuration, validations, and settings UI. Preserve the existing adapter and URL snapshots. Preserve system-backend protections.
3. Add AWS SDK dependencies, credential configuration for both containers, the Converse wrapper, and model/profile discovery.
4. Add native structured-output support and teacher capability validation; adapt Ollama-specific options and labels.
5. Test with SDK `stub_responses`, without AWS access: plain generation, structured requests, mixed content blocks, stop reasons, usage units, option translation, discovery pagination/failure, credential errors, throttling, and saved configuration after backend edits.
6. Add controller/catalog coverage and a refinement integration test with an Ollama student and stubbed Bedrock teacher. Verify one reference trial is reused, successive revisions run, failures pause chaining, and all completion conditions work.
7. Run Rails tests through Docker Compose (`docker compose exec app bin/rails test` when running). Rebuild and refresh both application and worker containers after dependency changes using the project's Compose workflow.
8. With deliberately configured AWS access, perform a small paid smoke test: one plain request, one schema-constrained evaluation, then a tiny refinement. Check the chosen model/profile, region, permissions, and worker credentials before a longer run.

Keep streaming, per-backend AWS accounts, custom endpoints, automatic price lookup, and broad model-family support out of the first implementation. A useful first release is one verified teacher model/profile, the existing local student, and the full refinement flow.
