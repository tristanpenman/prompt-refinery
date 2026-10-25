require "test_helper"

class ResponseTest < ActiveSupport::TestCase
  setup do
    @trial = create_trial
    @response = @trial.responses.first
  end

  test "defaults to pending" do
    assert_predicate @response, :pending?
  end

  test "requires a trial, test suite revision case, and valid status" do
    response = Response.new(status: "unknown")

    assert_not response.valid?
    assert_includes response.errors[:trial], "must exist"
    assert_includes response.errors[:test_suite_revision_case], "must exist"
    assert_includes response.errors[:status], "is not included in the list"
  end

  test "allows only one response per test case in a trial" do
    duplicate = @trial.responses.build(
      test_suite_revision_case: @response.test_suite_revision_case,
      rendered_prompt: @response.rendered_prompt
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:test_suite_revision_case_id], "has already been taken"
  end

  test "requires the test case to belong to the trial's test suite revision" do
    other_trial = create_trial(test_suite: create_test_suite(name: "Other"))
    response = @trial.responses.build(
      test_suite_revision_case: other_trial.responses.first.test_suite_revision_case,
      rendered_prompt: "Hello"
    )

    assert_not response.valid?
    assert_includes response.errors[:test_suite_revision_case], "must belong to the trial's test suite revision"
  end

  test "reaches the test case revision it was rendered from" do
    assert_equal({ "topic" => "Ruby" }, @response.test_case_revision.values)
  end

  test "calculates tokens per second from the eval count and duration" do
    assert_nil @response.tokens_per_second

    @response.assign_attributes(eval_count: 50, eval_duration: 0)
    assert_nil @response.tokens_per_second

    @response.eval_duration = 2_000_000_000
    assert_equal 25.0, @response.tokens_per_second
  end
end
