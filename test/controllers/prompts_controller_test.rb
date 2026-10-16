require "test_helper"

class PromptsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_encrypted_token = ENV["RAILS_AUTH_TOKEN"]
    ENV["RAILS_AUTH_TOKEN"] = TokenAuthenticator.encrypt("test-token")
    post login_path, params: { token: "test-token" }
  end

  teardown do
    PromptsController.ollama_client_class = ::Ollama::Client
    ENV["RAILS_AUTH_TOKEN"] = @original_encrypted_token
  end

  test "shows a prompt form for the selected model" do
    get prompt_path(model: "gemma3:4b")

    assert_response :success
    assert_select "h1", text: "gemma3:4b"
    assert_select "form[action=?]", prompt_path
    assert_select "textarea[name=question]"
  end

  test "generates and displays an answer" do
    client = Class.new do
      def generate(model:, prompt:)
        "#{model} says: #{prompt}"
      end
    end
    PromptsController.ollama_client_class = client

    post prompt_path,
      params: { model: "gemma3:4b", question: "Why is the sky blue?" },
      headers: { "Accept" => "text/vnd.turbo-stream.html, text/html" }

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_select "turbo-stream[action=replace][target=prompt_result]"
    assert_select ".answer", text: /gemma3:4b says: Why is the sky blue\?/
  end

  test "reports a generation error" do
    PromptsController.ollama_client_class = Class.new do
      def generate(model:, prompt:)
        raise ::Ollama::Client::Error, "Ollama timed out"
      end
    end

    post prompt_path, params: { model: "gemma3:4b", question: "Hello" }

    assert_response :bad_gateway
    assert_select "[role=alert]", text: /Ollama timed out/
  end

  test "rejects a blank question without contacting Ollama" do
    post prompt_path, params: { model: "gemma3:4b", question: "  " }

    assert_response :unprocessable_content
    assert_select "[role=alert]", text: /Enter a question/
  end

  test "supports a non-Turbo form submission" do
    PromptsController.ollama_client_class = Class.new do
      def generate(model:, prompt:)
        "Answer from #{model}: #{prompt}"
      end
    end

    post prompt_path, params: { model: "gemma3:4b", question: "Hello" }

    assert_response :success
    assert_equal "text/html", response.media_type
    assert_select "#prompt_result .answer", text: /Answer from gemma3:4b: Hello/
  end
end
