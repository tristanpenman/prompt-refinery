require "test_helper"

class PromptRevisionTest < ActiveSupport::TestCase
  test "cannot be changed after capture" do
    collection = Collection.create!(name: "Examples")
    prompt = collection.prompts.create!(name: "Greeting", template: "Hello")
    revision = PromptRevision.capture!(prompt)

    assert_not revision.update(template: "Changed")
    assert_includes revision.errors[:base], "Prompt revisions are immutable"
  end
end
