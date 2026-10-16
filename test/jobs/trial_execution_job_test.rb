require "test_helper"

class TrialExecutionJobTest < ActiveJob::TestCase
  setup do
    @collection = Collection.create!(name: "Examples")
    @collection.prompts.create!(name: "First", template: "First prompt", position: 1)
    @collection.prompts.create!(name: "Second", template: "Second prompt", position: 2)
    @trial = @collection.trials.create!(model: "gemma3:4b")
    @collection.prompts.each { |prompt| @trial.responses.create!(prompt: prompt) }
  end

  teardown do
    TrialExecutionJob.ollama_client_class = ::Ollama::Client
  end

  test "records responses sequentially and completes the trial" do
    calls = []
    TrialExecutionJob.ollama_client_class = Class.new do
      define_method(:generate) do |model:, prompt:|
        calls << [ model, prompt ]
        "Response to #{prompt}"
      end
    end

    TrialExecutionJob.perform_now(@trial)

    assert_equal [ [ "gemma3:4b", "First prompt" ], [ "gemma3:4b", "Second prompt" ] ], calls
    assert_predicate @trial.reload, :completed?
    assert_not_nil @trial.started_at
    assert_not_nil @trial.completed_at
    assert_equal [ "Response to First prompt", "Response to Second prompt" ], @trial.responses.map(&:content)
    assert @trial.responses.all?(&:completed?)
  end

  test "records an individual failure and continues the trial" do
    TrialExecutionJob.ollama_client_class = Class.new do
      def generate(model:, prompt:)
        raise ::Ollama::Client::Error, "Generation failed" if prompt == "First prompt"

        "Generated successfully"
      end
    end

    TrialExecutionJob.perform_now(@trial)

    assert_predicate @trial.reload, :failed?
    assert_equal [ "failed", "completed" ], @trial.responses.map(&:status)
    assert_equal "Generation failed", @trial.responses.first.error
    assert_equal "Generated successfully", @trial.responses.second.content
  end
end
