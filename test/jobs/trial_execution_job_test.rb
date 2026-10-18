require "test_helper"

class TrialExecutionJobTest < ActiveJob::TestCase
  setup do
    @collection = Collection.create!(name: "Examples")
    @collection.prompts.create!(name: "First", template: "First prompt", position: 1)
    @collection.prompts.create!(name: "Second", template: "Second prompt", position: 2)
    @trial = create_trial(collection: @collection)
  end

  teardown do
    TrialExecutionJob.client_factory = Inference::Client
  end

  test "records responses sequentially and completes the trial" do
    calls = []
    client_class = Class.new do
      define_method(:generate) do |model:, prompt:|
        calls << [ model, prompt ]
        "Response to #{prompt}"
      end
    end
    TrialExecutionJob.client_factory = factory_for(client_class)
    @collection.prompts.first.update!(template: "This edit happened after the trial was created")

    TrialExecutionJob.perform_now(@trial)

    assert_equal [ [ "gemma3:4b", "First prompt" ], [ "gemma3:4b", "Second prompt" ] ], calls
    assert_predicate @trial.reload, :completed?
    assert_not_nil @trial.started_at
    assert_not_nil @trial.completed_at
    assert_equal [ "Response to First prompt", "Response to Second prompt" ], @trial.responses.map(&:content)
    assert @trial.responses.all?(&:completed?)
  end

  test "records an individual failure and continues the trial" do
    client_class = Class.new do
      def generate(model:, prompt:)
        raise ::Ollama::Client::Error, "Generation failed" if prompt == "First prompt"

        "Generated successfully"
      end
    end
    TrialExecutionJob.client_factory = factory_for(client_class)

    TrialExecutionJob.perform_now(@trial)

    assert_predicate @trial.reload, :failed?
    assert_equal [ "failed", "completed" ], @trial.responses.map(&:status)
    assert_equal "Generation failed", @trial.responses.first.error
    assert_equal "Generated successfully", @trial.responses.second.content
  end

  private

  def factory_for(client_class)
    Class.new do
      define_singleton_method(:for) { |_backend, **_options| client_class.new }
    end
  end
end
