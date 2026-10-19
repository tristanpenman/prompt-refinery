require "test_helper"

class TrialComparisonsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_encrypted_token = ENV["RAILS_AUTH_TOKEN"]
    ENV["RAILS_AUTH_TOKEN"] = TokenAuthenticator.encrypt("test-token")
    post login_path, params: { token: "test-token" }

    @prompt = create_prompt(template: "Say hello about {{topic}}")
    @test_suite = create_test_suite
    @baseline = create_trial(prompt: @prompt, test_suite: @test_suite, model: "baseline-model")
    @trial = create_trial(prompt: @prompt, test_suite: @test_suite, model: "current-model")
    @baseline.responses.first.update!(status: :completed, content: "**Baseline** answer")
    @trial.responses.first.update!(status: :completed, content: "**Current** answer")
  end

  teardown do
    ENV["RAILS_AUTH_TOKEN"] = @original_encrypted_token
  end

  test "lists trials that share a test case, whichever prompt they ran" do
    other_prompt = create_prompt(template: "Describe {{topic}}")
    other_prompt_trial = create_trial(prompt: other_prompt, test_suite: @test_suite, model: "other-prompt-model")
    unrelated = create_trial(prompt: @prompt, test_suite: create_test_suite(name: "Unrelated"), model: "unrelated-model")

    get compare_trial_path(@trial)

    assert_response :success
    assert_select "h2", text: "Choose a baseline"
    assert_select "a[href=?]", compare_trial_path(@trial, baseline: @baseline.id), text: "Trial ##{@baseline.id}"
    assert_select "a[href=?]", compare_trial_path(@trial, baseline: other_prompt_trial.id)
    assert_select "a[href=?]", compare_trial_path(@trial, baseline: unrelated.id), count: 0
  end

  test "matches test cases across test suite revisions" do
    @test_suite.update!(name: "Renamed topics")
    @test_suite.test_cases.create!(values: { "topic" => "Rust" }, position: 1)
    later = create_trial(prompt: @prompt, test_suite: @test_suite, model: "later-model")

    get compare_trial_path(later, baseline: @baseline.id)

    assert_response :success
    assert_select ".trial-comparisons article", count: 1
  end

  test "shows common test case responses with the baseline on the left" do
    get compare_trial_path(@trial, baseline: @baseline.id)

    assert_response :success
    assert_select "h2", text: "Common test cases"
    assert_select ".trial-comparisons article", count: 1 do
      assert_select "h3", text: "Test case #1"
      assert_select ".prompt-change-warning", count: 0
      assert_select ".comparison-response .revision-badge", text: "r1", count: 2
      assert_select ".comparison-response:nth-child(1)", text: /Baseline.*Baseline answer/m
      assert_select ".comparison-response:nth-child(2)", text: /Current.*Current answer/m
      assert_select ".markdown-content strong", count: 2
    end
  end

  test "warns when the prompt contents differ" do
    @trial.responses.first.update!(rendered_prompt: "Say hello differently")

    get compare_trial_path(@trial, baseline: @baseline.id)

    assert_response :success
    assert_select ".trial-comparisons article h3", text: /Test case #1/ do
      assert_select ".prompt-change-warning[aria-label=?]", "Prompt contents changed", text: "⚠"
    end
  end

  test "rejects a baseline without a test case in common" do
    unrelated = create_trial(prompt: @prompt, test_suite: create_test_suite(name: "Unrelated"))

    get compare_trial_path(@trial, baseline: unrelated.id)

    assert_response :not_found
  end
end
