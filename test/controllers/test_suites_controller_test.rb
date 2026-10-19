require "test_helper"

class TestSuitesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_encrypted_token = ENV["RAILS_AUTH_TOKEN"]
    ENV["RAILS_AUTH_TOKEN"] = TokenAuthenticator.encrypt("test-token")
    post login_path, params: { token: "test-token" }
  end

  teardown do
    ENV["RAILS_AUTH_TOKEN"] = @original_encrypted_token
  end

  test "lists test suites" do
    test_suite = TestSuite.create!(name: "Topics", variables: [ "topic", "audience" ])
    test_suite.test_cases.create!(values: { "topic" => "Ruby", "audience" => "beginners" })

    get test_suites_path

    assert_response :success
    assert_select "th", text: "Revision"
    assert_select "th", text: "Draft"
    assert_select "tr", text: /Topics\s+N\/A\s+Draft\s+topic, audience\s+1/
  end

  test "shows the latest recorded revision and draft state" do
    test_suite = TestSuite.create!(name: "Topics", variables: [ "topic" ])
    test_case = test_suite.test_cases.create!(values: { "topic" => "Ruby" })
    TestSuiteRevision.capture!(test_suite)

    get test_suites_path
    assert_select "tr", text: /Topics\s+r1\s+Recorded/

    test_case.update!(values: { "topic" => "Rust" })

    get test_suites_path
    assert_select "tr", text: /Topics\s+r1\s+Draft/

    get test_suite_path(test_suite)
    assert_select "p", text: /Latest revision:\s+r1/
    assert_select "a[href=?]", revisions_test_suite_path(test_suite), text: "View revision history"
    assert_select "p", text: /There are draft changes/
  end

  test "switches between active and archived test suites" do
    active = TestSuite.create!(name: "Active suite")
    archived = TestSuite.create!(name: "Archived suite")
    archived.archive!

    get test_suites_path

    assert_response :success
    assert_select "a", text: active.name
    assert_select "a", text: archived.name, count: 0

    get test_suites_path(archived: true)

    assert_response :success
    assert_select "h2", text: "Archived test suites"
    assert_select "a", text: archived.name
    assert_select "a", text: active.name, count: 0
  end

  test "creates and updates a test suite" do
    assert_difference "TestSuite.count", 1 do
      post test_suites_path, params: { test_suite: { name: "Topics", variable_list: "topic, audience" } }
    end

    test_suite = TestSuite.last
    assert_redirected_to test_suite
    assert_equal [ "topic", "audience" ], test_suite.variables

    patch test_suite_path(test_suite), params: { test_suite: { name: "Subjects", variable_list: "subject" } }

    assert_redirected_to test_suite
    assert_equal [ "Subjects", [ "subject" ] ], test_suite.reload.attributes.values_at("name", "variables")
  end

  test "rerenders the form when a test suite is invalid" do
    test_suite = TestSuite.create!(name: "Topics", variables: [ "topic" ])

    patch test_suite_path(test_suite), params: { test_suite: { name: "Topics", variable_list: "two words" } }

    assert_response :unprocessable_content
    assert_select ".form-error", text: /Variables must be names/
    assert_select "textarea[name='test_case[values][topic]']"
  end

  test "shows a field for each variable" do
    test_suite = TestSuite.create!(name: "Topics", variables: [ "topic", "audience" ])
    test_suite.test_cases.create!(values: { "topic" => "Ruby", "audience" => "beginners" })

    get test_suite_path(test_suite)

    assert_response :success
    assert_select "textarea[name='test_case[values][topic]']", text: "Ruby"
    assert_select "textarea[name='test_case[values][audience]']", count: 2
    assert_select "h2", text: "Add test case"
  end

  test "asks for variables before test cases can be added" do
    test_suite = TestSuite.create!(name: "Empty")

    get test_suite_path(test_suite)

    assert_response :success
    assert_select "p", text: "Add variables to this test suite before adding test cases."
  end

  test "archives and unarchives a test suite" do
    test_suite = TestSuite.create!(name: "Topics", variables: [ "topic" ])
    test_suite.test_cases.create!(values: { "topic" => "Ruby" })

    assert_no_difference [ "TestSuite.count", "TestCase.count" ] do
      delete test_suite_path(test_suite)
    end

    assert_redirected_to test_suites_path
    assert_not_nil test_suite.reload.archived_at

    get test_suite_path(test_suite)

    assert_response :success
    assert_select "h1 .status--archived", text: "Archived"
    assert_select "textarea", count: 0
    assert_select ".archived-prompt-card dd", text: "Ruby"
    assert_select "h2", text: "Add test case", count: 0

    patch test_suite_path(test_suite), params: { test_suite: { name: "Changed" } }
    assert_redirected_to test_suite
    assert_equal "Topics", test_suite.reload.name

    patch unarchive_test_suite_path(test_suite)

    assert_redirected_to test_suite
    assert_nil test_suite.reload.archived_at
  end
end
