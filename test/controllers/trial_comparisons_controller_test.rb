require "test_helper"

class TrialComparisonsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_encrypted_token = ENV["RAILS_AUTH_TOKEN"]
    ENV["RAILS_AUTH_TOKEN"] = TokenAuthenticator.encrypt("test-token")
    post login_path, params: { token: "test-token" }

    @collection = Collection.create!(name: "Examples")
    @prompt = @collection.prompts.create!(name: "Greeting", template: "Say hello", position: 0)
    @baseline = create_trial(collection: @collection, model: "baseline-model")
    @trial = create_trial(collection: @collection, model: "current-model")
    @baseline.responses.find_by!(prompt: @prompt).update!(status: :completed, content: "Baseline answer")
    @trial.responses.find_by!(prompt: @prompt).update!(status: :completed, content: "Current answer")
  end

  teardown do
    ENV["RAILS_AUTH_TOKEN"] = @original_encrypted_token
  end

  test "lists only trials from the same collection with a prompt in common" do
    @prompt.soft_delete!
    replacement = @collection.prompts.create!(name: "Replacement", template: "A new prompt", position: 0)
    unrelated = create_trial(collection: @collection, model: "unrelated-model")
    other_collection = Collection.create!(name: "Other")
    other_collection.prompts.create!(name: "Greeting", template: "Say hello", position: 0)
    other_trial = create_trial(collection: other_collection, model: "other-model")

    get compare_trial_path(@trial)

    assert_response :success
    assert_select "h2", text: "Choose a baseline"
    assert_select "a[href=?]", compare_trial_path(@trial, baseline: @baseline.id), text: "Trial ##{@baseline.id}"
    assert_select "a[href=?]", compare_trial_path(@trial, baseline: unrelated.id), count: 0
    assert_select "a[href=?]", compare_trial_path(@trial, baseline: other_trial.id), count: 0
    assert_equal replacement, unrelated.responses.first.prompt
  end

  test "shows common prompt responses with the baseline on the left" do
    get compare_trial_path(@trial, baseline: @baseline.id)

    assert_response :success
    assert_select "h2", text: "Common prompts"
    assert_select ".trial-comparisons article", count: 1 do
      assert_select "h3", text: "Prompt #1"
      assert_select ".prompt-change-warning", count: 0
      assert_select ".comparison-response .revision-badge", text: "r1", count: 2
      assert_select ".comparison-response:nth-child(1)", text: /Baseline.*Baseline answer/m
      assert_select ".comparison-response:nth-child(2)", text: /Current.*Current answer/m
    end
  end

  test "warns when the prompt contents differ" do
    @trial.responses.find_by!(prompt: @prompt).update!(rendered_prompt: "Say hello differently")

    get compare_trial_path(@trial, baseline: @baseline.id)

    assert_response :success
    assert_select ".trial-comparisons article h3", text: /Prompt #1/ do
      assert_select ".prompt-change-warning[aria-label=?]", "Prompt contents changed", text: "⚠"
    end
  end

  test "rejects a baseline without a prompt in common" do
    @prompt.soft_delete!
    @collection.prompts.create!(name: "Replacement", template: "A new prompt", position: 0)
    unrelated = create_trial(collection: @collection)

    get compare_trial_path(@trial, baseline: unrelated.id)

    assert_response :not_found
  end
end
