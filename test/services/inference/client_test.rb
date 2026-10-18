require "test_helper"

class Inference::ClientTest < ActiveSupport::TestCase
  test "builds an Ollama client using the backend URL" do
    backend = Backend.new(adapter: "ollama", base_url: "http://edge-board.local:8080")

    client = Inference::Client.for(backend)

    assert_instance_of Ollama::Client, client
    assert_equal backend.base_url, client.instance_variable_get(:@base_url)
  end

  test "rejects an unsupported adapter" do
    backend = Backend.new(base_url: "http://example.test")
    backend.adapter = "unsupported"

    error = assert_raises(Inference::Client::UnsupportedAdapter) do
      Inference::Client.for(backend)
    end

    assert_equal "Unsupported inference adapter: unsupported", error.message
  end
end
