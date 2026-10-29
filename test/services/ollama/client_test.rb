require "test_helper"

class Ollama::ClientTest < ActiveSupport::TestCase
  test "completion preserves content, metric names and units, and request options" do
    metrics = {
      "prompt_eval_count" => 12, "eval_count" => 34,
      "load_duration" => 100, "prompt_eval_duration" => 200,
      "eval_duration" => 300, "total_duration" => 600
    }
    requests = []
    client = client_returning({ "message" => { "content" => "Answer" }, **metrics, "done" => true }, requests)
    schema = { type: "object" }
    options = { temperature: 0, num_ctx: 16384 }

    completion = client.complete(model: "teacher", prompt: "Question", format: schema, options: options)

    assert_instance_of Inference::Completion, completion
    assert_equal "Answer", completion.content
    assert_equal metrics, completion.metrics
    assert_equal [ [ "api/chat", {
      body: { model: "teacher", messages: [ { role: "user", content: "Question" } ], stream: false, format: schema, options: options },
      read_timeout: Ollama::Client::GENERATION_TIMEOUT
    } ] ], requests
    assert_same Inference::Completion, Ollama::Client::Completion
  end

  test "generate returns text and missing metrics stay absent" do
    client = client_returning({ "message" => { "content" => "Answer" } })

    assert_equal "Answer", client.generate(model: "student", prompt: "Question")
    assert_equal({}, client.complete(model: "student", prompt: "Question").metrics)
  end

  test "invalid generation responses retain Ollama errors under the shared error type" do
    client = client_returning({})

    error = assert_raises(Inference::Error) { client.complete(model: "student", prompt: "Question") }

    assert_instance_of Ollama::Client::Error, error
    assert_match(/Ollama returned an invalid generation response/, error.message)
  end

  test "invalid JSON retains the Ollama error message" do
    client = Ollama::Client.new
    client.define_singleton_method(:request) { |*args, **kwargs| Struct.new(:body).new("invalid JSON") }

    error = assert_raises(Inference::Error) { client.generate(model: "student", prompt: "Question") }

    assert_instance_of Ollama::Client::Error, error
    assert_match(/Ollama returned an invalid generation response/, error.message)
  end

  private

  def client_returning(body, requests = [])
    Ollama::Client.new.tap do |client|
      client.define_singleton_method(:request) do |path, **kwargs|
        requests << [ path, kwargs ]
        Struct.new(:body).new(JSON.generate(body))
      end
    end
  end
end
