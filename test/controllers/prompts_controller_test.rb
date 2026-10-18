require "test_helper"

class PromptsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_encrypted_token = ENV["RAILS_AUTH_TOKEN"]
    ENV["RAILS_AUTH_TOKEN"] = TokenAuthenticator.encrypt("test-token")
    post login_path, params: { token: "test-token" }
    @backend = Backend.ensure_system_default!
  end

  teardown do
    PromptsController.client_factory = Inference::Client
    ENV["RAILS_AUTH_TOKEN"] = @original_encrypted_token
  end

  test "shows a prompt form for the selected model" do
    get prompt_path(model: "gemma3:4b", backend_id: @backend.id)

    assert_response :success
    assert_select ".prompt-page > header" do
      assert_select ".eyebrow", text: "Prompt model"
      assert_select "h1", text: "gemma3:4b"
      assert_select "p", text: "Ask a question and generate a response with this model on Local Ollama."
    end
    assert_select "form[action=?]", prompt_path
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
    PromptsController.client_factory = factory_for(client)

    post prompt_path,
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
        raise ::Ollama::Client::Error, "Ollama timed out"
      end
    end
    PromptsController.client_factory = factory_for(client)

    post prompt_path, params: { model: "gemma3:4b", backend_id: @backend.id, question: "Hello" }

    assert_response :bad_gateway
    assert_select "[role=alert]", text: /Ollama timed out/
  end

  test "rejects a blank question without contacting Ollama" do
    post prompt_path, params: { model: "gemma3:4b", backend_id: @backend.id, question: "  " }

    assert_response :unprocessable_content
    assert_select "[role=alert]", text: /Enter a question/
  end

  test "supports a non-Turbo form submission" do
    client = Class.new do
      def generate(model:, prompt:)
        "Answer from #{model}: #{prompt}"
      end
    end
    PromptsController.client_factory = factory_for(client)

    post prompt_path, params: { model: "gemma3:4b", backend_id: @backend.id, question: "Hello" }

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
    PromptsController.client_factory = factory

    post prompt_path, params: { model: "gemma3-4b", backend_id: edge.id, question: "Hello" }

    assert_response :success
    assert_equal edge, selected_backend
  end

  private

  def factory_for(client_class)
    Object.new.tap do |factory|
      factory.define_singleton_method(:for) { |_backend| client_class.new }
    end
  end
end
