require "test_helper"

class Settings::BackendsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_encrypted_token = ENV["RAILS_AUTH_TOKEN"]
    ENV["RAILS_AUTH_TOKEN"] = TokenAuthenticator.encrypt("test-token")
    post login_path, params: { token: "test-token" }
  end

  teardown do
    Settings::BackendsController.client_factory = Inference::Client
    ENV["RAILS_AUTH_TOKEN"] = @original_encrypted_token
  end

  test "lists all backends including the system backend" do
    system_backend = Backend.ensure_system_default!(base_url: "http://ollama:11434")
    Backend.create!(name: "Disabled board", base_url: "http://edge-board.local:8080", enabled: false)

    get settings_backends_path

    assert_response :success
    assert_select "h1", text: "Backends"
    assert_select "a[href=?]", settings_path, text: "← Settings"
    assert_select ".backend-list li", count: 2
    assert_select ".backend-list li", text: /#{system_backend.name}.*System.*Enabled/m
    assert_select ".backend-list li", text: /Disabled board.*Disabled/m
    assert_select "form[action=?]", test_connection_settings_backend_path(system_backend)
    assert_select "a[href=?]", edit_settings_backend_path(system_backend), text: "Edit"
  end

  test "edits a regular backend" do
    backend = Backend.create!(name: "Old board", base_url: "http://old-board.local:8080")

    get edit_settings_backend_path(backend)

    assert_response :success
    assert_select "input[name='backend[name]'][value='Old board']"
    assert_select "input[name='backend[base_url]'][value='http://old-board.local:8080']"
    assert_select "select[name='backend[adapter]']"
    assert_select "form[action=?]", settings_backend_path(backend)

    patch settings_backend_path(backend), params: {
      backend: {
        name: "New board",
        base_url: "https://new-board.example.test/ollama/",
        adapter: "ollama",
        enabled: "0"
      }
    }

    assert_redirected_to settings_backends_path
    backend.reload
    assert_equal "New board", backend.name
    assert_equal "https://new-board.example.test/ollama", backend.base_url
    assert_not backend.enabled?
  end

  test "only allows a system backend enabled status to be edited" do
    backend = Backend.ensure_system_default!(base_url: "http://ollama:11434")

    get edit_settings_backend_path(backend)

    assert_response :success
    assert_select "input[name='backend[enabled]']"
    assert_select "input[name='backend[name]']", count: 0
    assert_select "input[name='backend[base_url]']", count: 0
    assert_select "select[name='backend[adapter]']", count: 0
    assert_select "button", text: "Delete backend", count: 0

    patch settings_backend_path(backend), params: {
      backend: {
        name: "Forged name",
        base_url: "http://forged.example.test",
        adapter: "forged",
        enabled: "0"
      }
    }

    assert_redirected_to settings_backends_path
    backend.reload
    assert_equal Backend::DEFAULT_NAME, backend.name
    assert_equal "http://ollama:11434", backend.base_url
    assert_equal "ollama", backend.adapter
    assert_not backend.enabled?
  end

  test "deletes a regular backend but not the system backend" do
    backend = Backend.create!(name: "Disposable board", base_url: "http://disposable.local:8080")
    system_backend = Backend.ensure_system_default!(base_url: "http://ollama:11434")

    assert_difference "Backend.count", -1 do
      delete settings_backend_path(backend)
    end
    assert_redirected_to settings_backends_path

    assert_no_difference "Backend.count" do
      delete settings_backend_path(system_backend)
    end
    assert_redirected_to settings_backends_path
    follow_redirect!
    assert_select ".flash--alert", text: "The system backend cannot be deleted"
  end

  test "creates a backend" do
    assert_difference "Backend.count", 1 do
      post settings_backends_path, params: {
        backend: { name: "Edge board", base_url: "http://edge-board.local:8080/" }
      }
    end

    backend = Backend.find_by!(name: "Edge board")
    assert_equal "http://edge-board.local:8080", backend.base_url
    assert backend.enabled?
    assert_redirected_to settings_backends_path
    follow_redirect!
    assert_select ".flash--notice", text: "Backend created."
  end

  test "renders validation errors when creation fails" do
    assert_no_difference "Backend.count" do
      post settings_backends_path, params: {
        backend: { name: "Invalid", base_url: "file:///tmp/ollama" }
      }
    end

    assert_response :unprocessable_content
    assert_select "[role=alert]", text: /Base url must use HTTP or HTTPS/
  end

  test "tests a backend connection and reports its model count" do
    backend = Backend.create!(name: "Edge board", base_url: "http://edge-board.local:8080")
    client = Object.new
    client.define_singleton_method(:models) { [ { "name" => "one" }, { "name" => "two" } ] }
    factory = Object.new
    factory.define_singleton_method(:for) do |received_backend|
      raise "Wrong backend" unless received_backend == backend
      client
    end
    Settings::BackendsController.client_factory = factory

    post test_connection_settings_backend_path(backend)

    assert_redirected_to settings_backends_path
    follow_redirect!
    assert_select ".flash--notice", text: "Connected to Edge board. Found 2 models."
  end

  test "reports a backend connection failure" do
    backend = Backend.create!(name: "Offline board", base_url: "http://offline.local:8080")
    client = Object.new
    client.define_singleton_method(:models) { raise Inference::Error, "connection refused" }
    factory = Object.new
    factory.define_singleton_method(:for) { |_backend| client }
    Settings::BackendsController.client_factory = factory

    post test_connection_settings_backend_path(backend)

    assert_redirected_to settings_backends_path
    follow_redirect!
    assert_select ".flash--alert", text: "Could not connect to Offline board: connection refused"
  end

  test "rejects a malformed model list" do
    backend = Backend.create!(name: "Incompatible board", base_url: "http://incompatible.local:8080")
    client = Object.new
    client.define_singleton_method(:models) { { "models" => [] } }
    factory = Object.new
    factory.define_singleton_method(:for) { |_backend| client }
    Settings::BackendsController.client_factory = factory

    post test_connection_settings_backend_path(backend)

    assert_redirected_to settings_backends_path
    follow_redirect!
    assert_select ".flash--alert", text: /server returned an invalid model list/
  end
end
