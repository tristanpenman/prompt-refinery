require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_encrypted_token = ENV["RAILS_AUTH_TOKEN"]
    ENV["RAILS_AUTH_TOKEN"] = TokenAuthenticator.encrypt("test-token")
    post login_path, params: { token: "test-token" }
  end

  teardown do
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
    assert_select ".dashboard-panel", count: 2
    assert_select ".dashboard-panel h2", text: "Backends"
    assert_select ".dashboard-panel:not(#model-families) li", count: 2
    assert_select "a[href=?]", settings_backends_path(anchor: dom_id(system_backend)), text: system_backend.name
    assert_select "li", text: /ollama · Enabled · System/
    assert_select "a[href=?]", settings_backends_path(anchor: dom_id(disabled_backend)), text: disabled_backend.name
    assert_select "li", text: /ollama · Disabled/
    assert_select "a[href=?]", settings_backends_path, text: "View all"
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
end
