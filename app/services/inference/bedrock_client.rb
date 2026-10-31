module Inference
  class BedrockClient
    Error = Class.new(Inference::Error)

    def initialize(client: nil)
      @client = client
    end

    def models
      configured = ENV["BEDROCK_MODEL_IDS"].to_s.split(",").map(&:strip).reject(&:empty?).uniq
      return configured.map { |id| catalog_entry(id, id, "Amazon Bedrock", "configured") } if configured.any?

      foundations = client.list_foundation_models.model_summaries
      by_id = foundations.index_by(&:model_id)
      models = foundations.select { |model| text_model?(model) && model.inference_types_supported.include?("ON_DEMAND") }
        .map { |model| catalog_entry(model.model_id, model.model_name, model.provider_name, "foundation_model") }

      client.list_inference_profiles.each_page do |page|
        page.inference_profile_summaries.each do |profile|
          next unless profile.status == "ACTIVE"

          underlying = profile.models.map { |model| by_id[model.model_arn.split("/", 2).last] }
          # AWS can retain ACTIVE profiles for models absent from its foundation
          # catalog. They cannot be verified as supported text candidates.
          next if underlying.empty? || underlying.any?(&:nil?)
          next unless underlying.all? { |model| text_model?(model) }

          models << catalog_entry(profile.inference_profile_arn, profile.inference_profile_name,
            underlying.map(&:provider_name).uniq.join(", "), "inference_profile").tap do |entry|
            entry["details"]["profile_type"] = profile.type
            entry["details"]["model_ids"] = underlying.map(&:model_id).uniq
          end
        end
      end
      models.uniq { |model| model["name"] }
    rescue Aws::Errors::ServiceError => error
      context = error.context
      location = [ context&.operation_name, context&.config&.region ].compact.join(" in ")
      message = "Bedrock discovery failed (#{error.code || error.class.name.demodulize})"
      message += " during #{location}" if location.present?
      message += ": #{error.message}"
      request_id = context&.http_response&.headers&.[]("x-amzn-requestid")
      message += " Request ID: #{request_id}." if request_id.present?
      raise Error, redact_credentials(message)
    rescue Aws::Errors::MissingCredentialsError,
      Seahorse::Client::NetworkingError => error
      raise Error, "Bedrock discovery failed (#{error.class.name.demodulize}). Check AWS credentials, region, and discovery permissions."
    end

    def complete(**)
      raise Error, "Bedrock generation is not implemented yet."
    end

    def generate(**)
      raise Error, "Bedrock generation is not implemented yet."
    end

    private

    def redact_credentials(message)
      %w[AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_BEARER_TOKEN_BEDROCK]
        .filter_map { |key| ENV[key].presence }
        .sort_by { |value| -value.length }
        .reduce(message) { |text, secret| text.gsub(secret, "[REDACTED]") }
    end

    def client
      @client ||= Aws::Bedrock::Client.new(region: BedrockConfiguration.region,
        retry_limit: 2, http_open_timeout: 10, http_read_timeout: 30)
    end

    def text_model?(model)
      model.input_modalities.include?("TEXT") && model.output_modalities.include?("TEXT") &&
        model.model_lifecycle&.status == "ACTIVE"
    end

    def catalog_entry(id, display_name, provider, source)
      { "name" => id, "size" => nil,
        "details" => { "display_name" => display_name, "provider" => provider, "source" => source } }
    end
  end
end
