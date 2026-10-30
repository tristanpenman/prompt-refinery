module Inference
  # Region and credentials belong to the deployment, rather than a backend or run.
  module BedrockConfiguration
    def self.region
      value = ENV["AWS_REGION"].to_s.strip
      raise Inference::Error, "Set AWS_REGION to configure the Bedrock region." if value.empty?
      unless value.match?(/\A[a-z0-9]+(?:-[a-z0-9]+)+-\d+\z/)
        raise Inference::Error, "AWS_REGION must be a valid AWS region name."
      end

      value
    end

    def self.endpoint
      Aws::BedrockRuntime::EndpointProvider.new.resolve_endpoint(
        Aws::BedrockRuntime::EndpointParameters.new(region: region)
      ).url
    end
  end
end
