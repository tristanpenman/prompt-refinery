require "test_helper"

class PromptTemplateTest < ActiveSupport::TestCase
  test "lists the variables a template uses once each" do
    template = PromptTemplate.new("Explain {{topic}} to {{ audience }} using {{topic}}")

    assert_equal [ "topic", "audience" ], template.variables
  end

  test "ignores text that is not a variable placeholder" do
    assert_equal [], PromptTemplate.new("Use {{two words}} or {single} braces").variables
  end

  test "renders variable values" do
    template = PromptTemplate.new("Explain {{topic}} to {{ audience }}")

    assert_equal "Explain Ruby to beginners", template.render("topic" => "Ruby", "audience" => "beginners")
  end

  test "does not interpret placeholders inside values" do
    template = PromptTemplate.new("Explain {{topic}}")

    assert_equal "Explain {{audience}}", template.render("topic" => "{{audience}}")
  end

  test "raises when a value is missing" do
    assert_raises(KeyError) { PromptTemplate.new("Explain {{topic}}").render({}) }
  end
end
