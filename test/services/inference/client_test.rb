require "test_helper"

class Inference::ClientTest < ActiveSupport::TestCase
  test "can build an Ollama client from saved adapter configuration" do
    backend = Backend.new(adapter: "unsupported")
    client = Inference::Client.for(backend, adapter: "ollama", base_url: "http://saved.test")
    assert_instance_of Ollama::Client, client
    assert_equal "http://saved.test", client.instance_variable_get(:@base_url)
  end

  test "builds an Ollama client using the backend URL" do
    backend = Backend.new(adapter: "ollama", base_url: "http://edge-board.local:8080")

    client = Inference::Client.for(backend)

    assert_instance_of Ollama::Client, client
    assert_equal backend.base_url, client.instance_variable_get(:@base_url)
  end

  test "can override the current URL with a trial snapshot" do
    backend = Backend.new(adapter: "ollama", base_url: "http://current.local:8080")

    client = Inference::Client.for(backend, base_url: "http://snapshot.local:8080")

    assert_equal "http://snapshot.local:8080", client.instance_variable_get(:@base_url)
  end

  test "uses the saved adapter instead of the current backend adapter" do
    backend = Backend.new(adapter: "bedrock")
    client = Inference::Client.for(backend, adapter: "ollama", base_url: "http://saved.test")
    assert_instance_of Ollama::Client, client
    assert_equal "http://saved.test", client.instance_variable_get(:@base_url)
  end

  test "Bedrock configuration fails clearly until generation and discovery are implemented" do
    backend = Backend.new(adapter: "bedrock")
    error = assert_raises(Inference::Client::UnsupportedAdapter) do
      Inference::Client.for(backend, adapter: "bedrock")
    end
    assert_includes error.message, "not implemented yet"
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
