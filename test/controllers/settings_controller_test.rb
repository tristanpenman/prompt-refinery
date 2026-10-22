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
    assert_select ".dashboard-panel", count: 3
    assert_select ".dashboard-panel h2", text: "Backends"
    assert_select ".dashboard-panel:nth-child(1) li", count: 2
    assert_select "a[href=?]", settings_backends_path(anchor: dom_id(system_backend)), text: system_backend.name
    assert_select "li", text: /ollama · Enabled · System/
    assert_select "a[href=?]", settings_backends_path(anchor: dom_id(disabled_backend)), text: disabled_backend.name
    assert_select "li", text: /ollama · Disabled/
    assert_select "a[href=?]", settings_backends_path, text: "View all"
  end

  test "shows the three most recently refreshed models after model families" do
    backend = Backend.ensure_system_default!
    # Created together in a shuffled order, so only refreshed_at decides the order shown.
    [ 2, 0, 3, 1 ].each do |days_ago|
      travel_to(10.days.ago) { LanguageModel.create!(backend: backend, name: "model-#{days_ago}") }
        .update!(refreshed_at: days_ago.days.ago)
    end

    get settings_path

    assert_response :success
    assert_select ".dashboard-panel:nth-child(2)#model-families"
    assert_select ".dashboard-panel:nth-child(3)#models" do
      assert_select "h2", text: "Available Models"
      assert_select "a[href=?]", settings_models_path, text: "View all"
      assert_select "li", count: 3
      assert_select "li:nth-child(1) a[href=?]", playground_path(model: "model-0", backend_id: backend.id), text: "model-0"
      assert_select "li:nth-child(1) small", text: "Local Ollama · Refreshed less than a minute ago"
      assert_select "li:nth-child(2)", text: /model-1/
      assert_select "li:nth-child(3) small", text: "Local Ollama · Refreshed 2 days ago"
      assert_select "li", text: /model-3/, count: 0
      assert_select "p.dashboard-more", text: "...and 1 more."
    end
  end

  test "doesn't mention more models when there are three or fewer" do
    backend = Backend.ensure_system_default!
    3.times { |index| LanguageModel.create!(backend: backend, name: "model-#{index}") }

    get settings_path

    assert_select "#models li", count: 3
    assert_select "#models .dashboard-more", count: 0
  end

  test "doesn't link models on disabled backends to the playground" do
    disabled = Backend.create!(name: "Old server", base_url: "http://old.test:11434", enabled: false)
    LanguageModel.create!(backend: disabled, name: "llama3:8b")

    get settings_path

    assert_select "#models li", text: /llama3:8b\s+Old server · Refreshed/
    assert_select "#models li a", count: 0
  end

  test "only shows available models" do
    backend = Backend.ensure_system_default!
    LanguageModel.create!(backend: backend, name: "gemma3:4b")
    3.times { |index| LanguageModel.create!(backend: backend, name: "removed-#{index}", available: false) }

    get settings_path

    assert_select "#models li", count: 1
    assert_select "#models li", text: /gemma3:4b/
    assert_select "#models .dashboard-more", count: 0
  end

  test "shows an empty models panel when no models are available" do
    LanguageModel.create!(backend: Backend.ensure_system_default!, name: "gemma3:4b", available: false)

    get settings_path

    assert_select "#models li", count: 0
    assert_select "#models p", text: "No available models. Refresh models to find them on your backends."
  end

  test "shows an empty models panel without contacting backends" do
    Backend.ensure_system_default!

    get settings_path

    assert_select "#models p", text: "No available models. Refresh models to find them on your backends."
    assert_select "#models p a[href=?]", settings_models_path, text: "Refresh models"
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
