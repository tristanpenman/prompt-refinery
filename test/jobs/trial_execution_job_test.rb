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

  test "uses saved adapter and URL when executing a queued trial" do
    backend = Backend.create!(name: "Edge", base_url: "http://saved.test")
    trial = create_trial(prompt: @prompt, test_suite: @test_suite, backend: backend)
    saved = trial.inference_configuration
    backend.update!(base_url: "http://changed.test")
    received = nil
    client = Object.new
    client.define_singleton_method(:complete) do |**_args|
      Inference::Completion.new(content: "Saved configuration", metrics: {})
    end
    factory = Object.new
    factory.define_singleton_method(:for) do |_backend, **configuration|
      received = configuration
      client
    end
    TrialExecutionJob.client_factory = factory

    TrialExecutionJob.perform_now(trial.reload)

    assert_equal saved, received
    assert_equal "ollama", received[:adapter]
    assert_equal "http://saved.test", received[:base_url]
    assert_predicate trial.reload, :completed?
  end

  test "uses the saved Bedrock adapter and endpoint when executing a queued trial" do
    with_aws_region("us-east-1") do
      backend = Backend.create!(name: "AWS", adapter: "bedrock")
      trial = create_trial(prompt: @prompt, test_suite: @test_suite, backend: backend)
      saved = trial.inference_configuration
      backend.update!(name: "Renamed AWS")
      received = nil
      client = Object.new
      client.define_singleton_method(:complete) do |**_args|
        Inference::Completion.new(content: "Saved configuration", metrics: {})
      end
      factory = Object.new
      factory.define_singleton_method(:for) do |_backend, **configuration|
        received = configuration
        client
      end
      TrialExecutionJob.client_factory = factory

      TrialExecutionJob.perform_now(trial.reload)

      assert_equal saved, received
      assert_equal "https://bedrock-runtime.us-east-1.amazonaws.com", received[:base_url]
      assert_predicate trial.reload, :completed?
    end
  end

  test "records responses sequentially and completes the trial" do
    calls = []
    client_class = Class.new do
      define_method(:complete) do |model:, prompt:|
        calls << [ model, prompt ]
        Inference::Completion.new(content: "Response to #{prompt}", metrics: { "prompt_eval_count" => 12, "eval_count" => 34, "total_duration" => 2_000_000_000 })
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
    assert_equal [ [ 12, 34, 2_000_000_000 ] ] * 2, ordered_responses.pluck(:prompt_eval_count, :eval_count, :total_duration)
  end

  test "records an individual failure and continues the trial" do
    client_class = Class.new do
      def complete(model:, prompt:)
        raise Inference::Error, "Generation failed" if prompt == "First prompt"

        Inference::Completion.new(content: "Generated successfully", metrics: {})
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
