require "test_helper"

class TrialTest < ActiveSupport::TestCase
  setup do
    @collection = Collection.create!(name: "Examples")
  end

  test "requires a collection, model, and valid status" do
    trial = Trial.new(model: "", status: "unknown")

    assert_not trial.valid?
    assert_includes trial.errors[:collection], "must exist"
    assert_includes trial.errors[:model], "can't be blank"
    assert_includes trial.errors[:status], "is not included in the list"
  end

  test "defaults to pending" do
    trial = @collection.trials.create!(model: "gemma3:4b")

    assert_predicate trial, :pending?
  end

  test "destroys its responses" do
    prompt = @collection.prompts.create!(name: "Example", template: "Hello")
    trial = @collection.trials.create!(model: "gemma3:4b")
    response = trial.responses.create!(prompt: prompt)

    trial.destroy!

    assert_not Response.exists?(response.id)
  end

  test "prevents its collection from being deleted" do
    @collection.trials.create!(model: "gemma3:4b")

    assert_not @collection.destroy
    assert_includes @collection.errors[:base], "Cannot delete record because dependent trials exist"
  end
end
