require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_encrypted_token = ENV["RAILS_AUTH_TOKEN"]
    ENV["RAILS_AUTH_TOKEN"] = TokenAuthenticator.encrypt("correct-token")
  end

  teardown do
    ENV["RAILS_AUTH_TOKEN"] = @original_encrypted_token
  end

  test "redirects an unauthenticated visitor to login" do
    get root_path

    assert_redirected_to login_path(return_to: "/")
  end

  test "sets a persistent encrypted cookie after login" do
    travel_to Time.zone.local(2026, 10, 16, 12) do
      post login_path, params: { token: "correct-token" }

      assert_includes response.headers["Set-Cookie"], "expires=Sat, 16 Oct 2027 12:00:00 GMT"
    end

    assert_redirected_to root_path

    HomeController.ollama_client_class = empty_ollama_client
    get root_path
    assert_response :success
  ensure
    HomeController.ollama_client_class = ::Ollama::Client
  end

  test "rejects an incorrect token" do
    post login_path, params: { token: "incorrect-token" }

    assert_response :unprocessable_content
    assert_select "[role=alert]", text: "The token is incorrect."
  end

  test "accepts a token from the query string without retaining it in the URL" do
    get root_path(token: "correct-token")

    assert_redirected_to root_path
  end

  test "does not include an invalid query token in the login redirect" do
    get root_path(token: "incorrect-token")

    assert_redirected_to login_path(return_to: "/")
  end

  private

  def empty_ollama_client
    Class.new do
      def models
        []
      end
    end
  end
end
