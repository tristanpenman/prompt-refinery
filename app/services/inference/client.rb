module Inference
  class Client
    UnsupportedAdapter = Class.new(Inference::Error)

    def self.for(backend, base_url: backend.base_url)
      case backend.adapter
      when "ollama"
        Ollama::Client.new(base_url: base_url)
      else
        raise UnsupportedAdapter, "Unsupported inference adapter: #{backend.adapter}"
      end
    end
  end
end
