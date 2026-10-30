module Inference
  class Client
    UnsupportedAdapter = Class.new(Inference::Error)

    def self.for(backend, base_url: backend.base_url, adapter: backend.adapter)
      case adapter
      when "ollama"
        Ollama::Client.new(base_url: base_url)
      when "bedrock"
        raise UnsupportedAdapter, "Bedrock generation and model discovery are not implemented yet."
      else
        raise UnsupportedAdapter, "Unsupported inference adapter: #{adapter}"
      end
    end
  end
end
