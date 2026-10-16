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

  test "shows the three most recent entries in each panel" do
    models = 4.times.map do |index|
      { "name" => "model-#{index}", "modified_at" => (Time.zone.now - index.days).iso8601 }
    end
    HomeController.ollama_client_class = Class.new do
      define_method(:models) { models }
    end
    collections = 4.times.map do |index|
      Collection.create!(name: "Collection #{index}", created_at: Time.zone.now - index.days)
    end
    collections.first.trials.create!(model: "model-a", created_at: 1.hour.ago)
    collections.second.trials.create!(model: "model-b", created_at: 2.hours.ago)
    collections.third.trials.create!(model: "model-c", created_at: 3.hours.ago)
    collections.last.trials.create!(model: "model-d", created_at: 4.hours.ago)

    get root_path

    assert_response :success
    assert_select ".dashboard-panel", count: 3
    assert_select ".dashboard-panel:nth-child(1) li", count: 3
    assert_select ".dashboard-panel:nth-child(2) li", count: 3
    assert_select ".dashboard-panel:nth-child(3) li", count: 3
    assert_select "a", text: "model-3", count: 0
    assert_select "a", text: "Collection 3", count: 0
    assert_select "a[href=?]", models_path, text: "View all"
  end

  test "still shows collections and trials when Ollama is unavailable" do
    HomeController.ollama_client_class = Class.new do
      def models
        raise ::Ollama::Client::Error, "Could not connect to Ollama"
      end
    end
    collection = Collection.create!(name: "Examples")
    collection.trials.create!(model: "gemma3:4b")

    get root_path

    assert_response :success
    assert_select "[role=alert]", text: /Could not connect to Ollama/
    assert_select "a", text: "Examples"
    assert_select "a", text: /Examples · gemma3:4b/
  end
end
