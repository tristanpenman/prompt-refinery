require "test_helper"

class ResponseTest < ActiveSupport::TestCase
  setup do
    @collection = Collection.create!(name: "Examples")
    @prompt = @collection.prompts.create!(name: "Example", template: "Hello")
    @trial = create_trial(collection: @collection)
    @response = @trial.responses.find_by!(prompt: @prompt)
  end

  test "defaults to pending" do
    assert_predicate @response, :pending?
  end

  test "requires a trial, prompt, and valid status" do
    response = Response.new(status: "unknown")

    assert_not response.valid?
    assert_includes response.errors[:trial], "must exist"
    assert_includes response.errors[:prompt], "must exist"
    assert_includes response.errors[:status], "is not included in the list"
  end

  test "allows only one response per prompt in a trial" do
    duplicate = @trial.responses.build(
      prompt: @prompt,
      collection_revision_prompt: @response.collection_revision_prompt,
      rendered_prompt: @response.rendered_prompt
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:prompt_id], "has already been taken"
  end

  test "requires the prompt to belong to the trial collection" do
    other_collection = Collection.create!(name: "Other")
    other_prompt = other_collection.prompts.create!(name: "Other", template: "Hello")
    response = @trial.responses.build(
      prompt: other_prompt,
      collection_revision_prompt: @response.collection_revision_prompt,
      rendered_prompt: @response.rendered_prompt
    )

    assert_not response.valid?
    assert_includes response.errors[:prompt], "must belong to the trial's collection"
  end

  test "prevents its prompt from being deleted" do
    assert_not @prompt.destroy
    assert_includes @prompt.errors[:base], "Cannot delete record because dependent responses exist"
  end
end
