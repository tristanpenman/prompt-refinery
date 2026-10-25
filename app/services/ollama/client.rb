require "net/http"
require "json"

module Ollama
  class Client
    Error = Class.new(StandardError)
    OPEN_TIMEOUT = 2
    READ_TIMEOUT = 5
    GENERATION_TIMEOUT = 300
    METRICS = %w[prompt_eval_count eval_count load_duration prompt_eval_duration eval_duration total_duration].freeze

    # The generated content, and the token counts and timings Ollama reported
    # for it, keyed by the names in METRICS. Durations are in nanoseconds.
    Completion = Data.define(:content, :metrics)

    def initialize(base_url: ENV.fetch("OLLAMA_URL", "http://localhost:11434"))
      @base_url = base_url
    end

    def models
      parse(request("api/tags"), key: "models", description: "model list")
    end

    # format is "json" or a JSON schema for structured output, and options are
    # model parameters such as temperature and num_ctx.
    def generate(model:, prompt:, format: nil, options: nil)
      complete(model: model, prompt: prompt, format: format, options: options).content
    end

    # Like generate, but returns a Completion that includes Ollama's metrics.
    def complete(model:, prompt:, format: nil, options: nil)
      response = request(
        "api/chat",
        body: { model: model, messages: [ { role: "user", content: prompt } ], stream: false, format: format, options: options }.compact,
        read_timeout: GENERATION_TIMEOUT
      )
      body = parse(response, key: nil, description: "generation response")
      Completion.new(content: body.fetch("message").fetch("content"), metrics: body.slice(*METRICS))
    rescue KeyError => error
      raise Error, "Ollama returned an invalid generation response: #{error.message}"
    end

    private

    attr_reader :base_url

    def request(path, body: nil, read_timeout: READ_TIMEOUT)
      uri = URI.join("#{base_url.delete_suffix("/")}/", path)
      response = Net::HTTP.start(
        uri.host,
        uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: OPEN_TIMEOUT,
        read_timeout: read_timeout
      ) do |http|
        http.request(build_request(uri, body))
      end

      return response if response.is_a?(Net::HTTPSuccess)

      raise Error, "Ollama returned HTTP #{response.code}"
    rescue SocketError, SystemCallError, Timeout::Error, URI::InvalidURIError => error
      raise Error, "Could not connect to Ollama: #{error.message}"
    end

    def build_request(uri, body)
      return Net::HTTP::Get.new(uri) unless body

      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request.body = JSON.generate(body)
      request
    end

    def parse(response, key:, description:)
      body = JSON.parse(response.body)
      key ? body.fetch(key) : body
    rescue JSON::ParserError, KeyError => error
      raise Error, "Ollama returned an invalid #{description}: #{error.message}"
    end
  end
end
