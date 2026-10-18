module Inference
  class Client
    UnsupportedAdapter = Class.new(StandardError)

    def self.for(backend)
      case backend.adapter
      when "ollama"
        Ollama::Client.new(base_url: backend.base_url)
      else
        raise UnsupportedAdapter, "Unsupported inference adapter: #{backend.adapter}"
      end
    end
  end
end
