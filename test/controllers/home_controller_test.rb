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
      Collection.create!(
        name: "Collection #{index}",
        created_at: Time.zone.now - index.days,
        updated_at: Time.zone.now - index.days
      ).tap { |collection| collection.prompts.create!(name: "Prompt #{index}", template: "Hello") }
    end
    create_trial(collection: collections.first, model: "model-a", created_at: 1.hour.ago)
    create_trial(collection: collections.second, model: "model-b", created_at: 2.hours.ago)
    create_trial(collection: collections.third, model: "model-c", created_at: 3.hours.ago)
    create_trial(collection: collections.last, model: "model-d", created_at: 4.hours.ago)

    get root_path

    assert_response :success
    assert_select ".dashboard-panel", count: 3
    assert_select ".dashboard-panel:nth-child(1) li", count: 3
    assert_select ".dashboard-panel:nth-child(2) li", count: 3
    assert_select ".dashboard-panel:nth-child(3) li", count: 3
    assert_select "a", text: "model-3", count: 0
    assert_select "a", text: "Collection 3", count: 0
    assert_select "a[href=?]", models_path, text: "View all"
    assert_select ".dashboard-panel:nth-child(1) small", text: /^Updated /
    assert_select ".dashboard-panel:nth-child(2) small", text: /^Updated /
  end

  test "orders collections by when they were updated" do
    older = Collection.create!(name: "Created recently", created_at: 1.hour.ago, updated_at: 3.days.ago)
    newer = Collection.create!(name: "Updated recently", created_at: 3.days.ago, updated_at: 1.hour.ago)
    HomeController.ollama_client_class = Class.new do
      def models
        []
      end
    end

    get root_path

    assert_response :success
    collection_links = css_select(".dashboard-panel:nth-child(2) li > a").map(&:text)
    assert_equal [ newer.name, older.name ], collection_links
    assert_select ".dashboard-panel:nth-child(2) small", text: /Updated about 1 hour ago/
  end

  test "shows when a completed trial finished" do
    HomeController.ollama_client_class = Class.new do
      def models
        []
      end
    end
    collection = Collection.create!(name: "Examples")
    collection.prompts.create!(name: "Example", template: "Hello")
    completed_at = 2.hours.ago.change(usec: 0)
    create_trial(collection: collection, status: :completed, completed_at: completed_at)

    get root_path

    assert_response :success
    assert_select ".dashboard-panel:nth-child(3) small", text: /Completed about 2 hours ago/
    assert_select ".dashboard-panel:nth-child(3) time[datetime=?]", completed_at.iso8601
  end

  test "hides archived collections but retains their trials" do
    HomeController.ollama_client_class = Class.new do
      def models
        []
      end
    end
    collection = Collection.create!(name: "Archived examples")
    collection.prompts.create!(name: "Example", template: "Hello")
    trial = create_trial(collection: collection)
    collection.archive!

    get root_path

    assert_response :success
    assert_select ".dashboard-panel:nth-child(2) a", text: "Archived examples", count: 0
    assert_select ".dashboard-panel:nth-child(3) a[href=?]", trial_path(trial), text: /Archived examples/
  end

  test "still shows collections and trials when Ollama is unavailable" do
    HomeController.ollama_client_class = Class.new do
      def models
        raise ::Ollama::Client::Error, "Could not connect to Ollama"
      end
    end
    collection = Collection.create!(name: "Examples")
    collection.prompts.create!(name: "Example", template: "Hello")
    create_trial(collection: collection)

    get root_path

    assert_response :success
    assert_select "[role=alert]", text: /Could not connect to Ollama/
    assert_select "a", text: "Examples"
    assert_select "a", text: /Examples · gemma3:4b/
  end
end
