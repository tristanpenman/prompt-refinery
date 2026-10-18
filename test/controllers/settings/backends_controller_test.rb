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
    assert_select "h1", text: "Inference backends"
    assert_select ".backend-list li", count: 2
    assert_select ".backend-list li", text: /#{system_backend.name}.*System.*Enabled/m
    assert_select ".backend-list li", text: /Disabled board.*Disabled/m
    assert_select "form[action=?]", test_connection_settings_backend_path(system_backend)
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
    client.define_singleton_method(:models) { [{ "name" => "one" }, { "name" => "two" }] }
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
    client.define_singleton_method(:models) { raise Ollama::Client::Error, "connection refused" }
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
