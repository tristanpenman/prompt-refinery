require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_encrypted_token = ENV["RAILS_AUTH_TOKEN"]
    ENV["RAILS_AUTH_TOKEN"] = TokenAuthenticator.encrypt("test-token")
    post login_path, params: { token: "test-token" }
  end

  teardown do
    ENV["RAILS_AUTH_TOKEN"] = @original_encrypted_token
  end

  test "shows the three most recent entries in each panel" do
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
    4.times do |index|
      TestSuite.create!(name: "Test suite #{index}", updated_at: Time.zone.now - index.days)
    end

    get root_path

    assert_response :success
    assert_select ".dashboard-panel", count: 3
    assert_select ".dashboard-panel:nth-child(1) li", count: 3
    assert_select ".dashboard-panel:nth-child(2) li", count: 3
    assert_select ".dashboard-panel:nth-child(3) li", count: 3
    assert_select "a", text: "Collection 3", count: 0
    assert_select "a", text: "Test suite 3", count: 0
    assert_select "a[href=?]", settings_path, text: "Settings"
    assert_select "a[href=?]", test_suites_path, text: "View all"
    assert_select ".dashboard-panel:nth-child(1) small", text: /^Updated /
  end

  test "does not show models" do
    get root_path

    assert_response :success
    assert_select "h2", text: "Models", count: 0
  end

  test "orders collections by when they were updated" do
    older = Collection.create!(name: "Created recently", created_at: 1.hour.ago, updated_at: 3.days.ago)
    newer = Collection.create!(name: "Updated recently", created_at: 3.days.ago, updated_at: 1.hour.ago)

    get root_path

    assert_response :success
    collection_links = css_select(".dashboard-panel:nth-child(1) li > a").map(&:text)
    assert_equal [ newer.name, older.name ], collection_links
    assert_select ".dashboard-panel:nth-child(1) small", text: /Updated about 1 hour ago/
  end

  test "shows when a completed trial finished" do
    collection = Collection.create!(name: "Examples")
    collection.prompts.create!(name: "Example", template: "Hello")
    completed_at = 2.hours.ago.change(usec: 0)
    create_trial(collection: collection, status: :completed, completed_at: completed_at)

    get root_path

    assert_response :success
    assert_select ".dashboard-panel:nth-child(2) small", text: /Completed about 2 hours ago/
    assert_select ".dashboard-panel:nth-child(2) time[datetime=?]", completed_at.iso8601
  end

  test "hides archived collections but retains their trials" do
    collection = Collection.create!(name: "Archived examples")
    collection.prompts.create!(name: "Example", template: "Hello")
    trial = create_trial(collection: collection)
    collection.archive!

    get root_path

    assert_response :success
    assert_select ".dashboard-panel:nth-child(1) a", text: "Archived examples", count: 0
    assert_select ".dashboard-panel:nth-child(2) a[href=?]", trial_path(trial), text: /Archived examples/
  end

  test "hides archived test suites" do
    TestSuite.create!(name: "Archived suite").archive!

    get root_path

    assert_response :success
    assert_select ".dashboard-panel:nth-child(3) p", text: "No test suites yet."
  end
end
