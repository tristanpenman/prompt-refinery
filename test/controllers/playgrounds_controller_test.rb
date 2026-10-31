require "test_helper"

class PlaygroundsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_encrypted_token = ENV["RAILS_AUTH_TOKEN"]
    ENV["RAILS_AUTH_TOKEN"] = TokenAuthenticator.encrypt("test-token")
    post login_path, params: { token: "test-token" }
    @backend = Backend.ensure_system_default!
  end

  teardown do
    PlaygroundsController.client_factory = Inference::Client
    ENV["RAILS_AUTH_TOKEN"] = @original_encrypted_token
  end

  test "shows a prompt form for the selected model" do
    get playground_path(model: "gemma3:4b", backend_id: @backend.id)

    assert_response :success
    assert_select ".prompt-page > header" do
      assert_select ".eyebrow", text: "Prompt model"
      assert_select "h1", text: "gemma3:4b"
      assert_select "p", text: "Ask a question and generate a response with this model on Local Ollama."
    end
    assert_select "form[action=?]", playground_path
    assert_select "input[name=backend_id][value=?]", @backend.id.to_s
    assert_select "textarea[name=question]"
  end

  test "generates and displays an answer" do
    client = Class.new do
      def generate(model:, prompt:)
        <<~MARKDOWN
          ## #{model} says

          - **Answer:** #{prompt}
          - Use `clear formatting`

          <script>alert("unsafe")</script>
        MARKDOWN
      end
    end
    PlaygroundsController.client_factory = factory_for(client)

    post playground_path,
      params: { model: "gemma3:4b", backend_id: @backend.id, question: "Why is the sky blue?" },
      headers: { "Accept" => "text/vnd.turbo-stream.html, text/html" }

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_select "turbo-stream[action=replace][target=prompt_result]"
    assert_select ".answer .markdown-content" do
      assert_select "h2", text: "gemma3:4b says"
      assert_select "ul li", count: 2
      assert_select "strong", text: "Answer:"
      assert_select "code", text: "clear formatting"
      assert_select "script", count: 0
    end
    assert_not_includes response.body, "alert("
  end

  test "reports a generation error" do
    client = Class.new do
      def generate(model:, prompt:)
        raise Inference::Error, "Ollama timed out"
      end
    end
    PlaygroundsController.client_factory = factory_for(client)

    post playground_path, params: { model: "gemma3:4b", backend_id: @backend.id, question: "Hello" }

    assert_response :unprocessable_content
    assert_select "[role=alert]", text: /Ollama timed out/
  end

  test "Bedrock access errors are rendered in the Turbo result instead of a gateway response" do
    with_aws_region("us-east-1") do
      backend = Backend.create!(name: "AWS", adapter: "bedrock")
      runtime = Aws::BedrockRuntime::Client.new(region: "us-east-1", stub_responses: true)
      runtime.stub_responses(:converse, Aws::BedrockRuntime::Errors::AccessDeniedException.new(nil,
        "openai.gpt-6-luna is not available for this account. Contact AWS Sales."))
      client = Inference::BedrockClient.new(runtime:)
      factory = Object.new
      factory.define_singleton_method(:for) { |_| client }
      PlaygroundsController.client_factory = factory

      post playground_path,
        params: { model: "global.openai.gpt-6-luna", backend_id: backend.id, question: "Hello" },
        headers: { "Accept" => "text/vnd.turbo-stream.html, text/html" }

      assert_response :unprocessable_content
      assert_equal "text/vnd.turbo-stream.html", response.media_type
      assert_select "turbo-stream[action=replace][target=prompt_result]" do
        assert_select "[role=alert]" do
          assert_select "h2", text: "Unable to generate a response"
          assert_select "p", text: /AccessDeniedException.*openai.gpt-6-luna is not available for this account.*Contact AWS Sales/
        end
      end
    end
  end

  test "rejects a blank question without contacting Ollama" do
    post playground_path, params: { model: "gemma3:4b", backend_id: @backend.id, question: "  " }

    assert_response :unprocessable_content
    assert_select "[role=alert]", text: /Enter a question/
  end

  test "supports a non-Turbo form submission" do
    client = Class.new do
      def generate(model:, prompt:)
        "Answer from #{model}: #{prompt}"
      end
    end
    PlaygroundsController.client_factory = factory_for(client)

    post playground_path, params: { model: "gemma3:4b", backend_id: @backend.id, question: "Hello" }

    assert_response :success
    assert_equal "text/html", response.media_type
    assert_select "#prompt_result .answer", text: /Answer from gemma3:4b: Hello/
  end

  test "uses the selected backend for generation" do
    edge = Backend.create!(name: "RK3588", base_url: "http://edge.test:8080")
    selected_backend = nil
    factory = Object.new
    factory.define_singleton_method(:for) do |backend|
      selected_backend = backend
      Class.new do
        def generate(model:, prompt:)
          "#{model}: #{prompt}"
        end
      end.new
    end
    PlaygroundsController.client_factory = factory

    post playground_path, params: { model: "gemma3-4b", backend_id: edge.id, question: "Hello" }

    assert_response :success
    assert_equal edge, selected_backend
  end

  test "Bedrock playground sends the selected profile and renders its answer" do
    with_aws_region("us-east-1") do
      backend = Backend.create!(name: "AWS", adapter: "bedrock")
      runtime = Aws::BedrockRuntime::Client.new(region: "us-east-1", stub_responses: true)
      runtime.stub_responses(:converse, output: { message: { role: "assistant", content: [ { text: "Bedrock answer" } ] } },
        stop_reason: "end_turn", usage: { input_tokens: 1, output_tokens: 2, total_tokens: 3 }, metrics: { latency_ms: 1 })
      client = Inference::BedrockClient.new(runtime:)
      factory = Object.new
      factory.define_singleton_method(:for) { |_| client }
      PlaygroundsController.client_factory = factory

      post playground_path, params: { model: "selected-profile", backend_id: backend.id, question: "Hello" },
        headers: { "Accept" => "text/vnd.turbo-stream.html" }

      assert_response :success
      assert_select "#prompt_result .answer", text: /Bedrock answer/
      assert_equal "selected-profile", runtime.api_requests.last[:params][:model_id]
      assert_equal "Hello", runtime.api_requests.last[:params][:messages].first[:content].first[:text]
    end
  end

  private

  def factory_for(client_class)
    Object.new.tap do |factory|
      factory.define_singleton_method(:for) { |_backend| client_class.new }
    end
  end
end
