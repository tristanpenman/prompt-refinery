# Inference backends

Every generation request goes through a configured backend. The local Compose Ollama service is the required default. Additional Ollama-compatible servers can be configured in settings.

Hosted backends are planned so a stronger teacher can refine prompts for a local student. Amazon Bedrock is the next implementation target; see [bedrock.md](bedrock.md) for details and [PLAN.md](../PLAN.md) for tasks. Direct Anthropic and OpenAI adapters remain future options.

## Current implementation

| Component       | Behavior                                                                                                  |
| --------------- | --------------------------------------------------------------------------------------------------------- |
| Backend records | Store `name`, `base_url`, `adapter`, `enabled`, and `system`. Only `ollama` is allowed.                   |
| System default  | Created from `OLLAMA_URL`, defaulting to `http://ollama:11434`. Only its enabled flag can be edited.      |
| Settings        | Create, edit, enable, disable, delete, and test connections. Backends used by trials cannot be deleted.   |
| URL validation  | Require HTTP(S) and a host; reject credentials, queries, and fragments. Remove trailing slashes.          |
| Trial snapshots | Save the backend name and URL at creation; execute requests against the saved URL.                        |
| Model catalog   | Refresh models per enabled backend. Mark missing models unavailable; preserve them when discovery fails.  |
| Metrics         | Store token counts and durations in nanoseconds on each trial response.                                   |

Backends used by refinements also cannot be deleted. Refinements snapshot student and teacher names and URLs, but execution still reads some current backend settings. Hosted support should close this gap and snapshot adapter-specific configuration, including Bedrock's region.

`Inference::Client.for(backend, base_url:)` currently returns an `Ollama::Client`. Controllers and jobs use this factory, which tests can replace with a fake.

```ruby
client.models
# => [{ "name" => ..., "size" => ..., "details" => {...} }, ...]

client.generate(model:, prompt:, format: nil, options: nil)
# => String

client.complete(model:, prompt:, format: nil, options: nil)
# => Completion(content:, metrics:)
```

`format` is a JSON schema. Current `options` are Ollama parameters, including `temperature` and `num_ctx`. Error handling currently rescues `Ollama::Client::Error`.

## Adding hosted backends

A refinement teacher makes two kinds of request:

1. A reference trial: one plain generation per test case, reused across iterations.
2. An evaluation: one structured request per iteration containing the reference and student outputs, returning case verdicts and a revised prompt.

Implement both through the existing client interface. Keep provider-specific translation in adapters, using official Ruby SDKs. Extend `Backend::ADAPTERS`, the database constraint, the client factory, and settings forms for each adapter.

| Concern        | Adapter responsibility                                                          |
| -------------- | ------------------------------------------------------------------------------- |
| Configuration  | Validate provider settings and execute from saved trial/refinement snapshots.   |
| Credentials    | Configure both `app` and `jobs`; keep secrets out of URLs, snapshots, and logs. |
| Model catalog  | Return usable text-model IDs, optional size, and provider metadata.             |
| Options        | Translate supported settings; omit Ollama-only `num_ctx` for hosted models.     |
| JSON output    | Map the evaluation schema to supported structured output; keep app validation.  |
| Output limits  | Allow enough tokens for case notes and the full prompt; reject truncation.      |
| Response       | Extract text and handle refusals, empty output, and other unsuccessful results. |
| Errors         | Wrap SDK errors in a shared `Inference::Error`; use bounded retries/timeouts.   |
| Metrics        | Map input/output tokens and measured elapsed time; leave unknown timings empty. |

Use a shared completion result rather than coupling new adapters to the Ollama namespace. Check schema requirements and model capabilities during implementation; avoid hard-coded model recommendations or pricing in this note.

For direct Anthropic or OpenAI adapters, start with environment-based API keys and fixed provider endpoints. Bedrock instead needs AWS credentials, region settings, and model or inference-profile identifiers, as described in [bedrock.md](bedrock.md).

Connection checks that list models establish discovery access, not permission to invoke every model. Preserve existing catalog entries on discovery errors and filter out unsupported models.

## Hosted models in the UI

Show the backend in model pickers and explain that a hosted teacher receives test cases and generated outputs. Hide or relabel Ollama-only context settings. Hosted backends will also appear in trials, the playground, and evaluations unless explicit role restrictions are added.

Teacher usage includes the reference trial plus every iteration's evaluation. Evaluation metrics need separate storage before the UI can show a complete token or cost total. Do not calculate generation throughput from wall time, which includes network latency and queueing.

## Ollama-compatible servers

Other Ollama servers and [rkllama](rkllama.md) use the existing `ollama` adapter. Verify that a server:

- Lists usable model names through `GET /api/tags`.
- Accepts non-streaming `POST /api/chat` requests and returns `message.content`.
- Accepts the listed model names unchanged.
- Supports JSON-schema `format` when used as a teacher.
- Reports metrics in the expected units.

Inside Docker, `localhost` refers to the Rails container. Use `host.docker.internal` for a server on the Docker host, or a LAN address reachable from both `app` and `jobs`. Add a dedicated adapter only when an observed incompatibility requires translation.

## Security and operations

User-editable URLs need request-time destination checks, an explicit allowlist for required LAN hosts, protection against cloud metadata access and unsafe redirects, and response-size limits. These checks remain future work.

Keep credentials out of logs and snapshots. Use fixed or SDK-resolved endpoints for hosted providers. Record backend health separately from application health: an unavailable model server should not make Rails' `/up` endpoint fail.

Implement and test the shared interface changes first, then the Bedrock adapter and a complete refinement with a local student. Defer additional providers and optional cost reporting until that flow works.
