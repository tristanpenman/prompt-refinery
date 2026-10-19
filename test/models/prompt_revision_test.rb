require "test_helper"

class PromptRevisionTest < ActiveSupport::TestCase
  test "cannot be changed after capture" do
    prompt = Prompt.create!(name: "Greeting", template: "Hello")
    revision = PromptRevision.capture!(prompt)

    assert_not revision.update(template: "Changed")
    assert_includes revision.errors[:base], "Prompt revisions are immutable"
  end

  test "reuses a revision when the prompt has not changed" do
    prompt = Prompt.create!(name: "Greeting", template: "Hello")

    assert_equal PromptRevision.capture!(prompt), PromptRevision.capture!(prompt)
  end

  test "captures a new revision after an edit" do
    prompt = Prompt.create!(name: "Greeting", template: "Hello")
    first = PromptRevision.capture!(prompt)
    prompt.update!(template: "Hello, world")

    second = PromptRevision.capture!(prompt)

    assert_equal [ 1, 2 ], [ first.version, second.version ]
    assert_equal [ "Hello", "Hello, world" ], [ first.template, second.template ]
  end
end
