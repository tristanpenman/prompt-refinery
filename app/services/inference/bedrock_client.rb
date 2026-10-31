module Inference
  class BedrockClient
    Error = Class.new(Inference::Error)

    def initialize(client: nil, runtime: nil)
      @client = client
      @runtime = runtime
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
      raise Error, service_error_message(error, "discovery")
    rescue Aws::Errors::MissingCredentialsError,
      Seahorse::Client::NetworkingError => error
      raise Error, "Bedrock discovery failed (#{error.class.name.demodulize}). Check AWS credentials, region, and discovery permissions."
    end

    def complete(model:, prompt:, format: nil, options: nil)
      raise Error, "Bedrock structured output is not implemented yet." if format

      config = (options || {}).stringify_keys
      unsupported = config.keys - %w[num_ctx num_predict max_tokens temperature top_p stop]
      raise Error, "Unsupported Bedrock options: #{unsupported.join(', ')}" if unsupported.any?

      inference = {}
      inference[:max_tokens] = config["max_tokens"] || config["num_predict"] if config.key?("max_tokens") || config.key?("num_predict")
      inference[:temperature] = config["temperature"] if config.key?("temperature")
      inference[:top_p] = config["top_p"] if config.key?("top_p")
      inference[:stop_sequences] = Array(config["stop"]) if config.key?("stop")
      request = { model_id: model, messages: [ { role: "user", content: [ { text: prompt } ] } ] }
      request[:inference_config] = inference if inference.any?
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
      reply = runtime.converse(**request)
      duration = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond) - started
      unless %w[end_turn stop_sequence].include?(reply.stop_reason)
        raise Error, "Bedrock did not complete the response (stop reason: #{reply.stop_reason.presence || 'missing'})."
      end
      message = reply.output&.message
      raise Error, "Bedrock returned an invalid assistant message." unless message&.role == "assistant"

      content = message.content.filter_map(&:text).join
      raise Error, "Bedrock returned an empty text response." if content.blank?

      metrics = { "total_duration" => duration,
        "prompt_eval_count" => reply.usage&.input_tokens, "eval_count" => reply.usage&.output_tokens }.compact
      Completion.new(content:, metrics:)
    rescue Aws::Errors::ServiceError => error
      raise Error, service_error_message(error, "generation")
    rescue Aws::Errors::MissingCredentialsError, Seahorse::Client::NetworkingError => error
      raise Error, "Bedrock generation failed (#{error.class.name.demodulize}). Check AWS credentials and connectivity."
    end

    def generate(model:, prompt:, format: nil, options: nil)
      complete(model:, prompt:, format:, options:).content
    end

    private

    def runtime
      @runtime ||= Aws::BedrockRuntime::Client.new(region: BedrockConfiguration.region,
        retry_limit: 2, http_open_timeout: 10, http_read_timeout: 300)
    end

    def service_error_message(error, operation)
      context = error.context
      location = [ context&.operation_name, context&.config&.region ].compact.join(" in ")
      message = "Bedrock #{operation} failed (#{error.code || error.class.name.demodulize})"
      message += " during #{location}" if location.present?
      message += ": #{error.message}"
      request_id = context&.http_response&.headers&.[]("x-amzn-requestid")
      message += " Request ID: #{request_id}." if request_id.present?
      redact_credentials(message)
    end

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
