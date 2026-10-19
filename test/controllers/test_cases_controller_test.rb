require "test_helper"

class TestCasesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_encrypted_token = ENV["RAILS_AUTH_TOKEN"]
    ENV["RAILS_AUTH_TOKEN"] = TokenAuthenticator.encrypt("test-token")
    post login_path, params: { token: "test-token" }
    @test_suite = TestSuite.create!(name: "Topics", variables: [ "topic", "audience" ])
  end

  teardown do
    ENV["RAILS_AUTH_TOKEN"] = @original_encrypted_token
  end

  test "creates and updates a test case" do
    assert_difference "TestCase.count", 1 do
      post test_suite_test_cases_path(@test_suite), params: {
        test_case: { position: 0, values: { topic: "Ruby", audience: "beginners" } }
      }
    end

    test_case = TestCase.last
    assert_redirected_to @test_suite

    patch test_suite_test_case_path(@test_suite, test_case), params: {
      test_case: { position: 1, values: { topic: "Rust", audience: "experts" } }
    }

    assert_redirected_to @test_suite
    assert_equal [ 1, { "topic" => "Rust", "audience" => "experts" } ], test_case.reload.attributes.values_at("position", "values")
  end

  test "reports invalid test cases" do
    assert_no_difference "TestCase.count" do
      post test_suite_test_cases_path(@test_suite), params: {
        test_case: { position: 0, values: { topic: "Ruby", tone: "formal" } }
      }
    end

    assert_redirected_to @test_suite
    assert_match "Values are missing audience", flash[:alert]
    assert_match "Values include unknown variables tone", flash[:alert]
  end

  test "soft deletes a test case" do
    test_case = @test_suite.test_cases.create!(values: { "topic" => "Ruby", "audience" => "beginners" })

    assert_no_difference "TestCase.count" do
      delete test_suite_test_case_path(@test_suite, test_case)
    end

    assert_redirected_to @test_suite
    assert_not_nil test_case.reload.deleted_at
    assert_not_includes @test_suite.test_cases.reload, test_case
  end

  test "does not access a test case through another test suite" do
    test_case = @test_suite.test_cases.create!(values: { "topic" => "Ruby", "audience" => "beginners" })
    other_suite = TestSuite.create!(name: "Other", variables: [ "topic", "audience" ])

    patch test_suite_test_case_path(other_suite, test_case), params: {
      test_case: { position: 1, values: { topic: "Rust", audience: "experts" } }
    }

    assert_response :not_found
  end

  test "rejects changes while the test suite is archived" do
    test_case = @test_suite.test_cases.create!(values: { "topic" => "Ruby", "audience" => "beginners" })
    @test_suite.archive!

    delete test_suite_test_case_path(@test_suite, test_case)

    assert_redirected_to @test_suite
    assert_nil test_case.reload.deleted_at
  end
end
