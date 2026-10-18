require "test_helper"

class EvaluationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_encrypted_token = ENV["RAILS_AUTH_TOKEN"]
    ENV["RAILS_AUTH_TOKEN"] = TokenAuthenticator.encrypt("test-token")
    post login_path, params: { token: "test-token" }
    @collection = Collection.create!(name: "Summaries")
    @backend = Backend.ensure_system_default!
  end

  teardown do
    EvaluationsController.client_factory = Inference::Client
    ENV["RAILS_AUTH_TOKEN"] = @original_encrypted_token
  end

  test "shows the available collections" do
    get evaluate_path(model: "gemma3:4b", backend_id: @backend.id)

    assert_response :success
    assert_select "h1", text: "gemma3:4b"
    assert_select "option[value=?]", @collection.id.to_s, text: "Summaries"
    assert_select "input[name=backend_id][value=?]", @backend.id.to_s
  end

  test "evaluates prompts sequentially and returns a Turbo Stream" do
    @collection.prompts.create!(name: "First", template: "First prompt", position: 1)
    @collection.prompts.create!(name: "Second", template: "Second prompt", position: 2)
    calls = []
    client = Class.new do
      define_method(:generate) do |model:, prompt:|
        calls << [ model, prompt ]
        "Response to #{prompt}"
      end
    end
    EvaluationsController.client_factory = factory_for(client)

    post evaluate_path,
      params: { model: "gemma3:4b", backend_id: @backend.id, collection_id: @collection.id },
      headers: { "Accept" => "text/vnd.turbo-stream.html, text/html" }

    assert_response :success
    assert_equal [ [ "gemma3:4b", "First prompt" ], [ "gemma3:4b", "Second prompt" ] ], calls
    assert_select "turbo-stream[action=replace][target=evaluation_results]"
    assert_select ".evaluation-result", count: 2
    assert_select ".evaluation-result", text: /Response to First prompt/
    assert_select ".evaluation-result", text: /Response to Second prompt/
  end

  test "continues after an individual prompt fails" do
    @collection.prompts.create!(name: "Broken", template: "Fail", position: 0)
    @collection.prompts.create!(name: "Working", template: "Succeed", position: 1)
    client = Class.new do
      def generate(model:, prompt:)
        raise ::Ollama::Client::Error, "Generation failed" if prompt == "Fail"

        "Generated successfully"
      end
    end
    EvaluationsController.client_factory = factory_for(client)

    post evaluate_path, params: { model: "gemma3:4b", backend_id: @backend.id, collection_id: @collection.id }

    assert_response :success
    assert_select "[role=alert]", text: "Generation failed"
    assert_select ".evaluation-result", text: /Generated successfully/
  end

  private

  def factory_for(client_class)
    Object.new.tap do |factory|
      factory.define_singleton_method(:for) { |_backend| client_class.new }
    end
  end
end
