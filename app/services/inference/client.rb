module Inference
  class Client
    UnsupportedAdapter = Class.new(Inference::Error)

    def self.for(backend, base_url: backend.base_url, adapter: backend.adapter)
      case adapter
      when "ollama"
        Ollama::Client.new(base_url: base_url)
      when "bedrock"
        BedrockClient.new
      else
        raise UnsupportedAdapter, "Unsupported inference adapter: #{adapter}"
      end
    end
  end
end
