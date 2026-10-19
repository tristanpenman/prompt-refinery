require "test_helper"

class TrialExecutionJobTest < ActiveJob::TestCase
  setup do
    @prompt = create_prompt(template: "{{label}} prompt")
    @test_suite = create_test_suite(cases: [ { "label" => "First" }, { "label" => "Second" } ])
    @trial = create_trial(prompt: @prompt, test_suite: @test_suite)
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
    @prompt.update!(template: "This edit happened after the trial was created")
    @test_suite.test_cases.first.update!(values: { "label" => "Edited" })

    TrialExecutionJob.perform_now(@trial)

    assert_equal [ [ "gemma3:4b", "First prompt" ], [ "gemma3:4b", "Second prompt" ] ], calls
    assert_predicate @trial.reload, :completed?
    assert_not_nil @trial.started_at
    assert_not_nil @trial.completed_at
    assert_equal [ "Response to First prompt", "Response to Second prompt" ], ordered_responses.map(&:content)
    assert ordered_responses.all?(&:completed?)
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
    assert_equal [ "failed", "completed" ], ordered_responses.map(&:status)
    assert_equal "Generation failed", ordered_responses.first.error
    assert_equal "Generated successfully", ordered_responses.second.content
  end

  private

  def ordered_responses
    @trial.responses.joins(:test_suite_revision_case).order("test_suite_revision_cases.position")
  end

  def factory_for(client_class)
    Class.new do
      define_singleton_method(:for) { |_backend, **_options| client_class.new }
    end
  end
end
