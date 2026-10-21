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
    prompts = 4.times.map do |index|
      Prompt.create!(
        name: "Prompt #{index}",
        template: "Hello",
        created_at: Time.zone.now - index.days,
        updated_at: Time.zone.now - index.days
      )
    end
    create_trial(prompt: prompts.first, model: "model-a", created_at: 1.hour.ago)
    create_trial(prompt: prompts.second, model: "model-b", created_at: 2.hours.ago)
    create_trial(prompt: prompts.third, model: "model-c", created_at: 3.hours.ago)
    create_trial(prompt: prompts.last, model: "model-d", created_at: 4.hours.ago)
    4.times do |index|
      TestSuite.create!(name: "Test suite #{index}", updated_at: Time.zone.now - index.days)
    end

    get root_path

    assert_response :success
    assert_select ".dashboard-panel", count: 3
    assert_select ".dashboard-panel:nth-child(1) li", count: 3
    assert_select ".dashboard-panel:nth-child(2) li", count: 3
    assert_select ".dashboard-panel:nth-child(3) li", count: 3
    assert_select "a", text: "Prompt 3", count: 0
    assert_select "a[href=?]", prompts_path, text: "View all"
    assert_select "a", text: "Test suite 3", count: 0
    assert_select "a[href=?]", settings_path, text: "Settings"
    assert_select "a[href=?]", test_suites_path, text: "View all"
    assert_select ".dashboard-panel:nth-child(1) small", text: /^Updated /
  end

  test "links to refinements above settings" do
    get root_path

    assert_select ".dashboard-actions a:nth-child(1)[href=?]", refinements_path, text: "Refinements"
    assert_select ".dashboard-actions a:nth-child(2)[href=?]", settings_path, text: "Settings"
  end

  test "does not show models" do
    get root_path

    assert_response :success
    assert_select "h2", text: "Models", count: 0
  end

  test "orders prompts by when they were updated" do
    older = Prompt.create!(name: "Created recently", template: "Hello", created_at: 1.hour.ago, updated_at: 3.days.ago)
    newer = Prompt.create!(name: "Updated recently", template: "Hello", created_at: 3.days.ago, updated_at: 1.hour.ago)

    get root_path

    assert_response :success
    prompt_links = css_select(".dashboard-panel:nth-child(1) li > a").map(&:text)
    assert_equal [ newer.name, older.name ], prompt_links
    assert_select ".dashboard-panel:nth-child(1) small", text: /Updated about 1 hour ago/
  end

  test "shows when a completed trial finished" do
    completed_at = 2.hours.ago.change(usec: 0)
    create_trial(status: :completed, completed_at: completed_at)

    get root_path

    assert_response :success
    assert_select ".dashboard-panel:nth-child(3) small", text: /Completed about 2 hours ago/
    assert_select ".dashboard-panel:nth-child(3) time[datetime=?]", completed_at.iso8601
  end

  test "hides archived prompts but retains their trials" do
    prompt = create_prompt(name: "Example", template: "Hello")
    trial = create_trial(prompt: prompt)
    prompt.archive!

    get root_path

    assert_response :success
    assert_select ".dashboard-panel:nth-child(1) a", text: "Example", count: 0
    assert_select ".dashboard-panel:nth-child(3) a[href=?]", trial_path(trial), text: /Example · Topics · gemma3:4b/
  end

  test "hides archived test suites" do
    TestSuite.create!(name: "Archived suite").archive!

    get root_path

    assert_response :success
    assert_select ".dashboard-panel:nth-child(2) p", text: "No test suites yet."
  end
end
