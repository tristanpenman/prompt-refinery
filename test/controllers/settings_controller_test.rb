require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_encrypted_token = ENV["RAILS_AUTH_TOKEN"]
    ENV["RAILS_AUTH_TOKEN"] = TokenAuthenticator.encrypt("test-token")
    post login_path, params: { token: "test-token" }
    SettingsController.client_factory = client_factory(models: [])
  end

  teardown do
    SettingsController.client_factory = Inference::Client
    ENV["RAILS_AUTH_TOKEN"] = @original_encrypted_token
  end

  test "shows configured backends in a dashboard panel" do
    system_backend = Backend.ensure_system_default!(base_url: "http://ollama:11434")
    disabled_backend = Backend.create!(
      name: "Edge board",
      base_url: "http://edge-board.local:8080",
      enabled: false
    )

    get settings_path

    assert_response :success
    assert_select ".dashboard-page > header h1", text: "Settings"
    assert_select ".dashboard-panel", count: 3
    assert_select ".dashboard-panel h2", text: "Backends"
    assert_select ".dashboard-panel:nth-child(1) li", count: 2
    assert_select "a[href=?]", settings_backends_path(anchor: dom_id(system_backend)), text: system_backend.name
    assert_select "li", text: /ollama · Enabled · System/
    assert_select "a[href=?]", settings_backends_path(anchor: dom_id(disabled_backend)), text: disabled_backend.name
    assert_select "li", text: /ollama · Disabled/
    assert_select "a[href=?]", settings_backends_path, text: "View all"
  end

  test "shows the three most recent models after model families" do
    backend = Backend.ensure_system_default!
    models = 4.times.map do |index|
      { "name" => "model-#{index}", "modified_at" => (Time.zone.now - index.days).iso8601 }
    end
    SettingsController.client_factory = client_factory(models:)

    get settings_path

    assert_response :success
    assert_select ".dashboard-panel:nth-child(2)#model-families"
    assert_select ".dashboard-panel:nth-child(3)#models" do
      assert_select "h2", text: "Models"
      assert_select "a[href=?]", settings_models_path, text: "View all"
      assert_select "li", count: 3
      assert_select "a[href=?]", prompt_path(model: "model-0", backend_id: backend.id), text: "model-0"
      assert_select "a", text: "model-3", count: 0
      assert_select "small", text: /Local Ollama · Updated /
    end
  end

  test "refreshes models from every enabled backend on each load" do
    local = Backend.ensure_system_default!
    edge = Backend.create!(name: "RK3588", base_url: "http://edge.test:8080")
    calls = Hash.new(0)
    responses = {
      local.id => [ { "name" => "local-model", "modified_at" => 2.hours.ago.iso8601 } ],
      edge.id => [ { "name" => "edge-model", "modified_at" => 1.hour.ago.iso8601 } ]
    }
    SettingsController.client_factory = changing_client_factory(calls:, responses:)

    get settings_path

    assert_select "#models li", count: 2
    assert_select "#models a", text: "local-model"
    assert_select "#models a", text: "edge-model"

    responses[edge.id] = [ { "name" => "edge-model-new", "modified_at" => Time.current.iso8601 } ]
    get settings_path

    assert_select "#models a", text: "edge-model-new"
    assert_select "#models a", text: "edge-model", count: 0
    assert_equal 2, calls[local.id]
    assert_equal 2, calls[edge.id]
  end

  test "still shows settings when a backend is unavailable" do
    Backend.ensure_system_default!
    SettingsController.client_factory = client_factory(error: "Could not connect to Ollama")

    get settings_path

    assert_response :success
    assert_select "#models [role=alert]", text: /Local Ollama: Could not connect to Ollama/
    assert_select "#models p", text: "No models installed."
    assert_select ".dashboard-panel h2", text: "Backends"
  end

  test "lists model families with their model counts" do
    system_backend = Backend.ensure_system_default!(base_url: "http://ollama:11434")
    edge_backend = Backend.create!(name: "Edge board", base_url: "http://edge-board.local:8080")
    LanguageModel.create!(backend: system_backend, name: "llama3:8b")
    LanguageModel.create!(backend: system_backend, name: "gemma3:4b")
    LanguageModel.create!(backend: edge_backend, name: "gemma3:4b")

    get settings_path

    assert_select "#model-families" do
      assert_select "h2", text: "Model Families"
      assert_select "li", count: 2
      assert_select "li:nth-child(1)", text: /gemma3\s+2 models/
      assert_select "li:nth-child(2)", text: /llama3\s+1 model/
    end
  end

  test "shows an empty model families panel" do
    get settings_path

    assert_select "#model-families p", text: "No model families registered."
  end

  test "requires authentication" do
    delete logout_path

    get settings_path

    assert_redirected_to login_path(return_to: settings_path)
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
