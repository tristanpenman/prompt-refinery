require "test_helper"

class EvaluationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_encrypted_token = ENV["RAILS_AUTH_TOKEN"]
    ENV["RAILS_AUTH_TOKEN"] = TokenAuthenticator.encrypt("test-token")
    post login_path, params: { token: "test-token" }
    @prompt = Prompt.create!(name: "Summary", template: "Summarize {{topic}}")
    @backend = Backend.ensure_system_default!
  end

  teardown do
    EvaluationsController.client_factory = Inference::Client
    ENV["RAILS_AUTH_TOKEN"] = @original_encrypted_token
  end

  test "shows the active prompts" do
    Prompt.create!(name: "Archived", template: "Old").archive!

    get evaluate_path(model: "gemma3:4b", backend_id: @backend.id)

    assert_response :success
    assert_select "h1", text: "gemma3:4b"
    assert_select "option[value=?]", @prompt.id.to_s, text: "Summary"
    assert_select "option", text: "Archived", count: 0
    assert_select "input[name=backend_id][value=?]", @backend.id.to_s
  end

  test "evaluates the prompt as written and returns a Turbo Stream" do
    calls = []
    client = Class.new do
      define_method(:generate) do |model:, prompt:|
        calls << [ model, prompt ]
        "Response to #{prompt}"
      end
    end
    EvaluationsController.client_factory = factory_for(client)

    post evaluate_path,
      params: { model: "gemma3:4b", backend_id: @backend.id, prompt_id: @prompt.id },
      headers: { "Accept" => "text/vnd.turbo-stream.html, text/html" }

    assert_response :success
    assert_equal [ [ "gemma3:4b", "Summarize {{topic}}" ] ], calls
    assert_select "turbo-stream[action=replace][target=evaluation_results]"
    assert_select "h2", text: "Summary result"
    assert_select ".evaluation-result", text: /Response to Summarize \{\{topic\}\}/
  end

  test "shows a generation failure" do
    client = Class.new do
      def generate(model:, prompt:)
        raise Inference::Error, "Generation failed"
      end
    end
    EvaluationsController.client_factory = factory_for(client)

    post evaluate_path, params: { model: "gemma3:4b", backend_id: @backend.id, prompt_id: @prompt.id }

    assert_response :success
    assert_select ".evaluation-result [role=alert]", text: "Generation failed"
  end

  test "rejects an archived prompt" do
    @prompt.archive!

    post evaluate_path, params: { model: "gemma3:4b", backend_id: @backend.id, prompt_id: @prompt.id }

    assert_response :unprocessable_content
    assert_select "[role=alert]", text: /Choose an available prompt/
  end

  private

  def factory_for(client_class)
    Object.new.tap do |factory|
      factory.define_singleton_method(:for) { |_backend| client_class.new }
    end
  end
end
