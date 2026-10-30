require "test_helper"

class Inference::BedrockConfigurationTest < ActiveSupport::TestCase
  test "derives the endpoint from AWS_REGION without credentials or network access" do
    with_aws_region(" ap-southeast-2 ") do
      assert_equal "ap-southeast-2", Inference::BedrockConfiguration.region
      assert_equal "https://bedrock-runtime.ap-southeast-2.amazonaws.com", Inference::BedrockConfiguration.endpoint
    end
    with_aws_region("cn-north-1") do
      assert_equal "https://bedrock-runtime.cn-north-1.amazonaws.com.cn", Inference::BedrockConfiguration.endpoint
    end
  end

  test "reads region changes from the deployment environment" do
    with_aws_region("us-east-1") do
      assert_equal "https://bedrock-runtime.us-east-1.amazonaws.com", Inference::BedrockConfiguration.endpoint
      with_aws_region("us-west-2") do
        assert_equal "https://bedrock-runtime.us-west-2.amazonaws.com", Inference::BedrockConfiguration.endpoint
      end
    end
  end

  test "missing or invalid AWS_REGION produces an actionable error" do
    [ nil, "", " ", "http://custom.test", "not-a-region" ].each do |region|
      with_aws_region(region) do
        error = assert_raises(Inference::Error) { Inference::BedrockConfiguration.endpoint }
        assert_match(/AWS_REGION/, error.message)
      end
    end
  end

  test "region is not stored in backend or execution tables" do
    assert_not_includes Backend.column_names, "region"
    assert_not_includes Trial.column_names, "backend_region"
    assert_not_includes PromptRefinement.column_names, "student_backend_region"
    assert_not_includes PromptRefinement.column_names, "teacher_backend_region"
  end
end
