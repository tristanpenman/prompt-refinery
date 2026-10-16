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
    @collection.prompts.create!(name: "Example", template: "Hello")
    trial = create_trial(collection: @collection)

    assert_predicate trial, :pending?
  end

  test "cannot be created for an archived collection" do
    @collection.archive!

    error = assert_raises(ActiveRecord::RecordInvalid) do
      create_trial(collection: @collection)
    end

    assert_includes error.record.errors[:collection], "has been archived"
  end

  test "cannot be created for a collection without prompts" do
    error = assert_raises(ActiveRecord::RecordInvalid) do
      create_trial(collection: @collection)
    end

    assert_includes error.record.errors[:collection], "must contain at least one prompt"
  end

  test "destroys its responses" do
    prompt = @collection.prompts.create!(name: "Example", template: "Hello")
    trial = create_trial(collection: @collection)
    response = trial.responses.find_by!(prompt: prompt)

    trial.destroy!

    assert_not Response.exists?(response.id)
  end

  test "prevents its collection from being deleted" do
    @collection.prompts.create!(name: "Example", template: "Hello")
    create_trial(collection: @collection)

    assert_not @collection.destroy
    assert_includes @collection.errors[:base], "Cannot delete record because dependent trials exist"
  end
end
