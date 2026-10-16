require "net/http"
require "json"

module Ollama
  class Client
    Error = Class.new(StandardError)

    def initialize(base_url: ENV.fetch("OLLAMA_URL", "http://localhost:11434"))
      @base_url = base_url
    end

    def models
      response = request("api/tags")
      JSON.parse(response.body).fetch("models")
    rescue JSON::ParserError, KeyError => error
      raise Error, "Ollama returned an invalid model list: #{error.message}"
    end

    private

    attr_reader :base_url

    def request(path)
      uri = URI.join("#{base_url.delete_suffix("/")}/", path)
      response = Net::HTTP.start(
        uri.host,
        uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: 2,
        read_timeout: 5
      ) { |http| http.get(uri.request_uri) }

      return response if response.is_a?(Net::HTTPSuccess)

      raise Error, "Ollama returned HTTP #{response.code}"
    rescue SocketError, SystemCallError, Timeout::Error, URI::InvalidURIError => error
      raise Error, "Could not connect to Ollama: #{error.message}"
    end
  end
end
