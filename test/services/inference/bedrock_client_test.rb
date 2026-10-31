require "test_helper"

class Inference::BedrockClientTest < ActiveSupport::TestCase
  setup do
    @original_ids = ENV.delete("BEDROCK_MODEL_IDS")
    @sdk = Aws::Bedrock::Client.new(region: "us-east-1", stub_responses: true)
    @client = Inference::BedrockClient.new(client: @sdk)
  end

  teardown do
    ENV["BEDROCK_MODEL_IDS"] = @original_ids
  end

  test "filters foundations and paginates profiles preserving invocation ARNs" do
    @sdk.stub_responses(:list_foundation_models, model_summaries: [
      foundation("text"), foundation("profile-only", inference_types_supported: []),
      foundation("embedding", output_modalities: [ "EMBEDDING" ]),
      foundation("old", model_lifecycle: { status: "LEGACY" })
    ])
    @sdk.stub_responses(:list_inference_profiles, [
      { inference_profile_summaries: [ profile("first", "profile-only") ], next_token: "next" },
      { inference_profile_summaries: [ profile("second", "text") ] }
    ])

    models = @client.models

    assert_equal [ "text", "arn:aws:bedrock:us-east-1:123456789012:inference-profile/first",
      "arn:aws:bedrock:us-east-1:123456789012:inference-profile/second" ], models.map { |model| model["name"] }
    assert_nil models.first["size"]
    assert_equal "Provider", models.last["details"]["provider"]
    assert_equal "next", @sdk.api_requests.last[:params][:next_token]
  end

  test "configured identifiers bypass discovery" do
    ENV["BEDROCK_MODEL_IDS"] = " custom-id, custom-id, arn:aws:bedrock:us-east-1:123456789012:application-inference-profile/test "
    assert_equal 2, @client.models.size
    assert_empty @sdk.api_requests
  end

  test "a later discovery failure preserves existing availability" do
    with_aws_region("us-east-1") do
      backend = Backend.create!(name: "AWS", adapter: "bedrock")
      existing = backend.language_models.create!(name: "existing")
      @sdk.stub_responses(:list_foundation_models, model_summaries: [ foundation("text") ])
      @sdk.stub_responses(:list_inference_profiles, [
        { inference_profile_summaries: [ profile("first", "text") ], next_token: "next" },
        "AccessDeniedException"
      ])
      factory = Object.new
      client = @client
      factory.define_singleton_method(:for) { |_| client }

      result = Inference::ModelCatalog.new(backends: [ backend ], client_factory: factory).call

      assert_equal 1, result.errors.size
      assert existing.reload.available?
      assert_equal [ "existing" ], backend.language_models.pluck(:name)
    end
  end

  test "stale active profiles do not block discovery of supported models" do
    @sdk.stub_responses(:list_foundation_models, model_summaries: [ foundation("text") ])
    @sdk.stub_responses(:list_inference_profiles, inference_profile_summaries: [
      profile("unknown", "missing"), profile("supported", "text")
    ])
    assert_equal [ "text", profile("supported", "text")[:inference_profile_arn] ],
      @client.models.map { |model| model["name"] }
  end

  test "service errors include AWS diagnostics and redact credential values" do
    original_secret = ENV["AWS_SECRET_ACCESS_KEY"]
    ENV["AWS_SECRET_ACCESS_KEY"] = "discovery-test-secret"
    context = Seahorse::Client::RequestContext.new(
      operation_name: :list_foundation_models, config: @sdk.config)
    context.http_response.headers["x-amzn-requestid"] = "discovery-request-123"
    failure = Aws::Bedrock::Errors::UnrecognizedClientException.new(context,
      "The security token included in the request is invalid: discovery-test-secret")
    @sdk.stub_responses(:list_foundation_models, failure)

    error = assert_raises(Inference::BedrockClient::Error) { @client.models }

    assert_includes error.message, "UnrecognizedClientException"
    assert_includes error.message, "list_foundation_models in us-east-1"
    assert_includes error.message, "The security token included in the request is invalid"
    assert_includes error.message, "discovery-request-123"
    assert_includes error.message, "[REDACTED]"
    assert_not_includes error.message, "discovery-test-secret"
  ensure
    ENV["AWS_SECRET_ACCESS_KEY"] = original_secret
  end

  test "Converse sends the exact invocation ID and maps text and usage" do
    runtime = Aws::BedrockRuntime::Client.new(region: "us-east-1", stub_responses: true)
    runtime.stub_responses(:converse, completion_reply)
    client = Inference::BedrockClient.new(runtime:)
    result = client.complete(model: "profile-arn", prompt: "Hello", options: { num_ctx: 4096, num_predict: 100 })

    assert_equal "Hello world", result.content
    assert_equal 5, result.metrics["prompt_eval_count"]
    assert_equal 2, result.metrics["eval_count"]
    assert_operator result.metrics["total_duration"], :>=, 0
    assert_not result.metrics.key?("eval_duration")
    assert_equal({ model_id: "profile-arn", messages: [ { role: "user", content: [ { text: "Hello" } ] } ],
      inference_config: { max_tokens: 100 } }, runtime.api_requests.last[:params])
    assert_equal "Hello world", client.generate(model: "profile-arn", prompt: "Hello")
  end

  test "Converse leaves generation parameters to the model by default" do
    runtime = Aws::BedrockRuntime::Client.new(region: "us-east-1", stub_responses: true)
    runtime.stub_responses(:converse, completion_reply)
    Inference::BedrockClient.new(runtime:).generate(model: "text", prompt: "Hello")
    assert_not runtime.api_requests.last[:params].key?(:inference_config)
  end

  test "Converse rejects incomplete or blocked responses" do
    runtime = Aws::BedrockRuntime::Client.new(region: "us-east-1", stub_responses: true)
    client = Inference::BedrockClient.new(runtime:)
    %w[max_tokens guardrail_intervened content_filtered tool_use refusal unknown].each do |reason|
      runtime.stub_responses(:converse, completion_reply.merge(stop_reason: reason))
      error = assert_raises(Inference::Error) { client.generate(model: "text", prompt: "Hello") }
      assert_includes error.message, reason
    end
    runtime.stub_responses(:converse, completion_reply.merge(output: { message: { role: "assistant", content: [] } }))
    assert_raises(Inference::Error) { client.generate(model: "text", prompt: "Hello") }
  end

  test "Converse failures use the common error interface" do
    runtime = Aws::BedrockRuntime::Client.new(region: "us-east-1", stub_responses: true)
    runtime.stub_responses(:converse, "AccessDeniedException")
    error = assert_raises(Inference::Error) do
      Inference::BedrockClient.new(runtime:).generate(model: "text", prompt: "Hello")
    end
    assert_includes error.message, "Bedrock generation failed (AccessDeniedException)"
  end

  test "structured output and unknown options fail before sending a request" do
    runtime = Aws::BedrockRuntime::Client.new(region: "us-east-1", stub_responses: true)
    client = Inference::BedrockClient.new(runtime:)
    assert_raises(Inference::Error) { client.generate(model: "text", prompt: "Hello", format: {}) }
    assert_raises(Inference::Error) { client.generate(model: "text", prompt: "Hello", options: { seed: 1 }) }
    assert_empty runtime.api_requests
  end

  private

  def completion_reply
    { output: { message: { role: "assistant", content: [
      { text: "Hello" }, { reasoning_content: { reasoning_text: { text: "private reasoning", signature: "sig" } } },
      { text: " world" }
    ] } }, stop_reason: "end_turn", usage: { input_tokens: 5, output_tokens: 2, total_tokens: 7 },
      metrics: { latency_ms: 10 } }
  end

  def foundation(id, **overrides)
    { model_id: id, model_name: id.titleize, model_arn: "arn:aws:bedrock:us-east-1::foundation-model/#{id}",
      provider_name: "Provider", input_modalities: [ "TEXT" ], output_modalities: [ "TEXT" ],
      inference_types_supported: [ "ON_DEMAND" ], model_lifecycle: { status: "ACTIVE" } }.merge(overrides)
  end

  def profile(id, model_id)
    { inference_profile_id: id, inference_profile_name: id.titleize,
      inference_profile_arn: "arn:aws:bedrock:us-east-1:123456789012:inference-profile/#{id}",
      status: "ACTIVE", type: "SYSTEM_DEFINED",
      models: [ { model_arn: "arn:aws:bedrock:us-west-2::foundation-model/#{model_id}" } ] }
  end
end
