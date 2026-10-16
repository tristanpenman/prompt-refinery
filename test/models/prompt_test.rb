require "test_helper"

class PromptTest < ActiveSupport::TestCase
  setup do
    @collection = Collection.create!(name: "Examples")
  end

  test "requires a collection, name, and template" do
    prompt = Prompt.new(position: 0)

    assert_not prompt.valid?
    assert_includes prompt.errors[:collection], "must exist"
    assert_includes prompt.errors[:name], "can't be blank"
    assert_includes prompt.errors[:template], "can't be blank"
  end

  test "requires a non-negative integer position" do
    prompt = @collection.prompts.build(name: "Example", template: "Hello", position: -1)

    assert_not prompt.valid?
    assert_includes prompt.errors[:position], "must be greater than or equal to 0"
  end
end
