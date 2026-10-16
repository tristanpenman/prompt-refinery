require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_encrypted_token = ENV["RAILS_AUTH_TOKEN"]
    ENV["RAILS_AUTH_TOKEN"] = TokenAuthenticator.encrypt("test-token")
    post login_path, params: { token: "test-token" }
  end

  teardown do
    HomeController.ollama_client_class = ::Ollama::Client
    ENV["RAILS_AUTH_TOKEN"] = @original_encrypted_token
  end

  test "lists models returned by Ollama" do
    models = [
      {
        "name" => "gemma3:4b",
        "size" => 3_300_000_000,
        "details" => { "family" => "gemma3", "parameter_size" => "4.3B", "quantization_level" => "Q4_K_M" }
      }
    ]
    HomeController.ollama_client_class = Class.new do
      define_method(:models) { models }
    end

    get root_path

    assert_response :success
    assert_select "h2", text: "gemma3:4b"
    assert_select "li", text: /gemma3 · 4.3B · Q4_K_M/
    assert_select "a[href=?]", prompt_path(model: "gemma3:4b"), text: "Select"
  end

  test "reports an Ollama connection error" do
    HomeController.ollama_client_class = Class.new do
      def models
        raise ::Ollama::Client::Error, "Could not connect to Ollama"
      end
    end

    get root_path

    assert_response :success
    assert_select "[role=alert]", text: /Could not connect to Ollama/
  end
end
