require "test_helper"

class TestSuiteRevisionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_encrypted_token = ENV["RAILS_AUTH_TOKEN"]
    ENV["RAILS_AUTH_TOKEN"] = TokenAuthenticator.encrypt("test-token")
    post login_path, params: { token: "test-token" }
  end

  teardown do
    ENV["RAILS_AUTH_TOKEN"] = @original_encrypted_token
  end

  test "shows test suite revisions newest first with their test case snapshots" do
    test_suite = TestSuite.create!(name: "Topics", variables: [ "topic" ])
    test_case = test_suite.test_cases.create!(values: { "topic" => "Original topic" })
    TestSuiteRevision.capture!(test_suite)
    test_case.update!(values: { "topic" => "Updated topic" })
    TestSuiteRevision.capture!(test_suite)

    get revisions_test_suite_path(test_suite)

    assert_response :success
    assert_select ".editor-card", count: 2
    assert_select ".current-revision", text: /Revision 2/
    assert_select ".current-revision", text: /Updated topic/
    assert_select ".revision-list .editor-card", text: /Revision 1/
    assert_select ".revision-list .editor-card", text: /Original topic/
  end

  test "shows an empty state before the test suite is used" do
    test_suite = TestSuite.create!(name: "Draft")

    get revisions_test_suite_path(test_suite)

    assert_response :success
    assert_select ".current-revision", text: /Draft · will become r1/i
    assert_select ".notice", text: /No previous revisions yet/
  end
end
