require "test_helper"

class RefinementEvaluationTest < ActiveSupport::TestCase
  test "unwraps nested delimiters around a template" do
    assert_equal "Explain {{topic}}", RefinementEvaluation.unwrap_template("---\n---\nExplain {{topic}}\n---\n---")
    assert_equal "Explain {{topic}}", RefinementEvaluation.unwrap_template("  <template>\nExplain {{topic}}\n</template>\n")
    assert_equal "Explain {{topic}}", RefinementEvaluation.unwrap_template("<template>---\nExplain {{topic}}\n---</template>")
  end

  test "keeps delimiters that don't wrap the whole template" do
    template = "Explain {{topic}}\n---\nAnswer briefly."
    assert_equal template, RefinementEvaluation.unwrap_template(template)
    assert_equal "---\nExplain {{topic}}", RefinementEvaluation.unwrap_template("---\nExplain {{topic}}")
    assert_equal "---", RefinementEvaluation.unwrap_template("---\n---")
  end
end
