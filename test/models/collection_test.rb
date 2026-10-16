require "test_helper"

class CollectionTest < ActiveSupport::TestCase
  test "is valid without prompts" do
    assert_predicate Collection.new(name: "Writing styles"), :valid?
  end

  test "requires a name" do
    collection = Collection.new(name: "")

    assert_not collection.valid?
    assert_includes collection.errors[:name], "can't be blank"
  end

  test "returns prompts in position order" do
    collection = Collection.create!(name: "Summaries")
    second = collection.prompts.create!(name: "Detailed", template: "Explain {{topic}}", position: 2)
    first = collection.prompts.create!(name: "Short", template: "Summarize {{topic}}", position: 1)

    assert_equal [ first, second ], collection.prompts.reload.to_a
  end

  test "does not return soft-deleted prompts" do
    collection = Collection.create!(name: "Summaries")
    active = collection.prompts.create!(name: "Active", template: "Hello", position: 0)
    deleted = collection.prompts.create!(name: "Deleted", template: "Goodbye", position: 1)

    deleted.soft_delete!

    assert_equal [ active ], collection.prompts.reload.to_a
    assert_equal [ deleted ], collection.deleted_prompts.reload.to_a
  end

  test "destroys its prompts" do
    collection = Collection.create!(name: "Disposable")
    prompt = collection.prompts.create!(name: "Example", template: "Hello", position: 0)

    collection.destroy!

    assert_not Prompt.exists?(prompt.id)
  end
end
