require "test_helper"

class CollectionRevisionTest < ActiveSupport::TestCase
  setup do
    @collection = Collection.create!(name: "Examples")
    @prompt = @collection.prompts.create!(name: "Greeting", template: "Hello", position: 0)
  end

  test "reuses a revision when the collection has not changed" do
    first = CollectionRevision.capture!(@collection)
    second = CollectionRevision.capture!(@collection)

    assert_equal first, second
    assert_equal 1, @collection.collection_revisions.count
  end

  test "captures new collection and prompt revisions after an edit" do
    first = CollectionRevision.capture!(@collection)
    @prompt.update!(template: "Hello, world")

    second = CollectionRevision.capture!(@collection)

    assert_equal 1, first.version
    assert_equal 2, second.version
    assert_equal "Hello", first.prompt_revisions.first.template
    assert_equal "Hello, world", second.prompt_revisions.first.template
    assert_equal [ 1, 2 ], @prompt.prompt_revisions.order(:version).pluck(:version)
  end

  test "cannot be changed after capture" do
    revision = CollectionRevision.capture!(@collection)

    assert_not revision.update(name: "Changed")
    assert_includes revision.errors[:base], "Collection revisions are immutable"
  end
end
