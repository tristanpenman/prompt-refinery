# Compose supplies empty strings for optional variables. The AWS SDK signs
# requests with an empty session token if it is present, which invalidates
# otherwise valid IAM access-key credentials.
%w[AWS_SESSION_TOKEN AWS_BEARER_TOKEN_BEDROCK].each do |key|
  ENV.delete(key) if ENV[key].blank?
end
