require "test_helper"

class ModelsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_encrypted_token = ENV["RAILS_AUTH_TOKEN"]
    ENV["RAILS_AUTH_TOKEN"] = TokenAuthenticator.encrypt("test-token")
    post login_path, params: { token: "test-token" }
    @backend = Backend.ensure_system_default!
  end

  teardown do
    ModelsController.client_factory = Inference::Client
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
    ModelsController.client_factory = client_factory(models:)

    get models_path

    assert_response :success
    assert_select ".models-page > header" do
      assert_select ".eyebrow", text: "Prompt Refinery"
      assert_select "h1", text: "Available models"
      assert_select "p", text: "Models currently available from enabled inference backends."
    end
    assert_select "h2", text: "gemma3:4b"
    assert_select ".model-backend", text: "Backend: Local Ollama"
    assert_select "li", text: /gemma3 · 4.3B · Q4_K_M/
    assert_select "a[href=?]", prompt_path(model: "gemma3:4b", backend_id: @backend.id), text: "Select"
    assert_select "a[href=?]", evaluate_path(model: "gemma3:4b", backend_id: @backend.id), text: "Evaluate"
  end

  test "reports an Ollama connection error" do
    ModelsController.client_factory = client_factory(error: "Could not connect to Ollama")

    get models_path

    assert_response :success
    assert_select "[role=alert]", text: /Local Ollama is unavailable.*Could not connect to Ollama/m
  end

  test "lists models from all enabled backends and refreshes them on every load" do
    edge = Backend.create!(name: "RK3588", base_url: "http://edge.test:8080")
    disabled = Backend.create!(name: "Disabled", base_url: "http://disabled.test:8080", enabled: false)
    calls = Hash.new(0)
    responses = {
      @backend.id => [ { "name" => "local-model" } ],
      edge.id => [ { "name" => "edge-model" } ]
    }
    ModelsController.client_factory = changing_client_factory(calls:, responses:)

    get models_path

    assert_select "h2", text: "local-model"
    assert_select "h2", text: "edge-model"
    assert_select ".model-backend", text: "Backend: Local Ollama"
    assert_select ".model-backend", text: "Backend: RK3588"

    responses[edge.id] = [ { "name" => "updated-edge-model" } ]
    get models_path

    assert_select "h2", text: "updated-edge-model"
    assert_select "h2", text: "edge-model", count: 0
    assert_equal 2, calls[@backend.id]
    assert_equal 2, calls[edge.id]
    assert_not calls.key?(disabled.id)
  end

  test "keeps models from available backends when another backend fails" do
    edge = Backend.create!(name: "RK3588", base_url: "http://edge.test:8080")
    factory = Object.new
    factory.define_singleton_method(:for) do |backend|
      Object.new.tap do |client|
        client.define_singleton_method(:models) do
          raise Ollama::Client::Error, "connection refused" if backend == edge

          [ { "name" => "local-model" } ]
        end
      end
    end
    ModelsController.client_factory = factory

    get models_path

    assert_select "h2", text: "local-model"
    assert_select "[role=alert]", text: /RK3588 is unavailable.*connection refused/m
  end

  private

  def client_factory(models: nil, error: nil)
    client = Object.new
    client.define_singleton_method(:models) do
      raise Ollama::Client::Error, error if error

      models
    end
    Object.new.tap { |factory| factory.define_singleton_method(:for) { |_backend| client } }
  end

  def changing_client_factory(calls:, responses:)
    Object.new.tap do |factory|
      factory.define_singleton_method(:for) do |backend|
        Object.new.tap do |client|
          client.define_singleton_method(:models) do
            calls[backend.id] += 1
            responses.fetch(backend.id)
          end
        end
      end
    end
  end
end
