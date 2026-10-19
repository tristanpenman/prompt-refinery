require "test_helper"

class PromptTest < ActiveSupport::TestCase
  test "requires a name and template" do
    prompt = Prompt.new

    assert_not prompt.valid?
    assert_includes prompt.errors[:name], "can't be blank"
    assert_includes prompt.errors[:template], "can't be blank"
  end

  test "archives a prompt without deleting it" do
    prompt = Prompt.create!(name: "Greeting", template: "Hello")

    prompt.archive!

    assert_not_nil prompt.archived_at
    assert_not_includes Prompt.active, prompt
    assert_includes Prompt.archived, prompt
  end

  test "an archived prompt can only be unarchived" do
    prompt = Prompt.create!(name: "Greeting", template: "Hello")
    prompt.archive!

    assert_not prompt.update(template: "Changed")
    assert_includes prompt.errors[:base], "Archived prompts are read-only"

    prompt.unarchive!
    assert_nil prompt.archived_at
  end

  test "destroys its revisions" do
    prompt = Prompt.create!(name: "Greeting", template: "Hello")
    PromptRevision.capture!(prompt)

    assert_difference "PromptRevision.count", -1 do
      prompt.destroy!
    end
  end
end
