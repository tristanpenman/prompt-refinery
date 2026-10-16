require "net/http"
require "json"

module Ollama
  class Client
    Error = Class.new(StandardError)
    OPEN_TIMEOUT = 2
    READ_TIMEOUT = 5
    GENERATION_TIMEOUT = 300

    def initialize(base_url: ENV.fetch("OLLAMA_URL", "http://localhost:11434"))
      @base_url = base_url
    end

    def models
      parse(request("api/tags"), key: "models", description: "model list")
    end

    def generate(model:, prompt:)
      response = request(
        "api/generate",
        body: { model: model, prompt: prompt, stream: false },
        read_timeout: GENERATION_TIMEOUT
      )
      parse(response, key: "response", description: "generation response")
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
      JSON.parse(response.body).fetch(key)
    rescue JSON::ParserError, KeyError => error
      raise Error, "Ollama returned an invalid #{description}: #{error.message}"
    end
  end
end
