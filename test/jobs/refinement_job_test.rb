require "test_helper"

class RefinementJobTest < ActiveJob::TestCase
  setup do
    @backend = Backend.ensure_system_default!
    @prompt = create_prompt(template: "Explain {{topic}}")
    @test_suite = create_test_suite(cases: [ { "topic" => "Ruby" }, { "topic" => "Rails" } ])
    @refinement = PromptRefinement.create_for!(
      prompt: @prompt,
      test_suite: @test_suite,
      student: LanguageModel.create!(backend: @backend, name: "student:1b"),
      teacher: LanguageModel.create!(backend: @backend, name: "teacher:8b")
    )
    @refinement.start_iteration!
    @evaluations = []
  end

  teardown do
    TrialExecutionJob.client_factory = Inference::Client
    RefinementJob.client_factory = Inference::Client
  end

  test "runs one iteration and returns the refinement to pending" do
    use_client(evaluation_replies: [ evaluation_reply(verdicts: %w[match partial]) ])

    RefinementJob.perform_now(@refinement)

    assert_predicate @refinement.reload, :pending?
    reference = @refinement.reference_trial
    assert_equal [ "teacher:8b", @refinement.starting_prompt_revision ], [ reference.model, reference.prompt_revision ]
    assert_equal [ "Teacher: Explain Ruby", "Teacher: Explain Rails" ], ordered_contents(reference)

    iteration = @refinement.iterations.sole
    assert_predicate iteration, :completed?
    assert_equal 1, iteration.number
    assert_equal "Explain {{topic}}", iteration.prompt_revision.template
    assert_equal @refinement.prompt, iteration.prompt_revision.prompt
    assert_equal "student:1b", iteration.student_trial.model
    assert_equal [ "Student: Explain Ruby", "Student: Explain Rails" ], ordered_contents(iteration.student_trial)
    assert_equal 0.75, iteration.agreement
    assert_equal "Too long.", iteration.summary
    assert_equal "Asked for brevity.", iteration.change_summary
    assert_equal "Briefly explain {{topic}}", iteration.proposed_template
    case_ids = @refinement.test_suite_revision.test_suite_revision_cases.map { |test_case| test_case.id.to_s }
    assert_equal({ case_ids[0] => { "verdict" => "match", "notes" => "Note 1" }, case_ids[1] => { "verdict" => "partial", "notes" => "Note 2" } },
      iteration.case_evaluations)
    assert_not_nil iteration.started_at
    assert_not_nil iteration.completed_at
    assert_equal "Briefly explain {{topic}}", @refinement.prompt.reload.template
    assert_equal "Explain {{topic}}", @prompt.reload.template

    evaluation = @evaluations.sole
    assert_equal "teacher:8b", evaluation[:model]
    assert_equal RefinementEvaluation::FORMAT, evaluation[:format]
    assert_equal({ temperature: 0, num_ctx: 16384 }, evaluation[:options])
    assert_equal evaluation[:prompt], iteration.evaluation_prompt
    assert_includes evaluation[:prompt], "Current template:\n<template>\nExplain {{topic}}\n</template>"
    assert_includes evaluation[:prompt], "The template uses these variables: topic."
    assert_includes evaluation[:prompt], "Earlier attempts:\nNone. This is the first attempt."
    assert_includes evaluation[:prompt], <<~CASE.strip
      <test_case number="1">
      Variables:
      - topic: Ruby
      <reference_output>
      Teacher: Explain Ruby
      </reference_output>
      <student_output>
      Student: Explain Ruby
      </student_output>
      </test_case>
    CASE
  end

  test "reuses the reference trial and runs the proposed prompt in the next iteration" do
    use_client(evaluation_replies: [ evaluation_reply(verdicts: %w[miss miss]), evaluation_reply(verdicts: %w[match match], prompt: "Done {{topic}}") ])
    RefinementJob.perform_now(@refinement)
    reference = @refinement.reload.reference_trial

    @refinement.start_iteration!
    assert_no_difference -> { Trial.where(model: "teacher:8b").count } do
      RefinementJob.perform_now(@refinement)
    end

    assert_equal reference, @refinement.reload.reference_trial
    first, second = @refinement.iterations.to_a
    assert_equal 2, second.number
    assert_equal "Briefly explain {{topic}}", second.prompt_revision.template
    assert_equal [ "Student: Briefly explain Ruby", "Student: Briefly explain Rails" ], ordered_contents(second.student_trial)
    assert_equal 1.0, second.agreement
    assert_includes @evaluations.last[:prompt],
      "Iteration 1 (prompt r#{first.prompt_revision.version}): agreement 0%. Too long. Changes made: Asked for brevity."
  end

  test "removes delimiters copied around the proposed prompt" do
    use_client(evaluation_replies: [ evaluation_reply(verdicts: %w[match match], prompt: "---\n<template>\n---\nBriefly explain {{topic}}\n---\n</template>\n---") ])

    RefinementJob.perform_now(@refinement)

    assert_equal "Briefly explain {{topic}}", @refinement.iterations.sole.proposed_template
    assert_equal "Briefly explain {{topic}}", @refinement.prompt.reload.template
  end

  test "retries a rejected evaluation once with the reason" do
    use_client(evaluation_replies: [ "not json", evaluation_reply(verdicts: %w[match match]) ])

    RefinementJob.perform_now(@refinement)

    assert_equal 2, @evaluations.size
    assert @evaluations.last[:prompt].end_with?("Your previous reply was rejected: the reply is not valid JSON. Reply again, following the format exactly.")
    assert_predicate @refinement.iterations.sole, :completed?
  end

  test "fails the iteration when the evaluation is rejected twice" do
    use_client(evaluation_replies: [ evaluation_reply(verdicts: %w[match]), evaluation_reply(verdicts: %w[match match], prompt: "Explain {{subject}}") ])

    RefinementJob.perform_now(@refinement)

    iteration = @refinement.iterations.sole
    assert_predicate iteration, :failed?
    assert_equal "The teacher's evaluation was rejected twice: the prompt uses variable that the test suite doesn't have: subject.", iteration.error
    assert_includes iteration.evaluation_prompt, "Your previous reply was rejected: \"cases\" must have exactly 2 entries."
    assert_predicate @refinement.reload, :pending?
    assert_equal "Explain {{topic}}", @refinement.prompt.reload.template
  end

  test "fails the iteration without a reference when the reference trial fails" do
    use_client(evaluation_replies: [], failing_models: [ "teacher:8b" ])

    RefinementJob.perform_now(@refinement)

    iteration = @refinement.iterations.sole
    assert_predicate iteration, :failed?
    assert_match(/\AThe reference trial \(#\d+\) failed, so there is nothing to compare with\.\z/, iteration.error)
    assert_nil @refinement.reload.reference_trial
    assert_predicate @refinement, :pending?
    assert @refinement.can_run_iteration?
  end

  test "fails the iteration when every student response fails" do
    use_client(evaluation_replies: [], failing_models: [ "student:1b" ])

    RefinementJob.perform_now(@refinement)

    iteration = @refinement.iterations.sole
    assert_predicate iteration, :failed?
    assert_equal "Every response in the student trial (##{iteration.student_trial.id}) failed.", iteration.error
    assert_empty @evaluations
  end

  test "counts a failed student response as a miss" do
    use_client(evaluation_replies: [ evaluation_reply(verdicts: %w[match match]) ], failing_student_prompts: [ "Explain Rails" ])

    RefinementJob.perform_now(@refinement)

    iteration = @refinement.iterations.sole
    assert_predicate iteration, :completed?
    assert_equal 0.5, iteration.agreement
    assert_includes @evaluations.sole[:prompt], "<student_output>\n(No output: the request failed.)\n</student_output>"
    assert_equal [ "match", "miss" ], iteration.case_evaluations.values.map { |evaluation| evaluation["verdict"] }
  end

  test "records an evaluation request that couldn't be sent" do
    use_client(evaluation_replies: [ Inference::Error.new("Could not connect to Ollama: refused") ])

    assert_no_enqueued_jobs do
      RefinementJob.perform_now(@refinement, run_to_completion: true)
    end

    assert_predicate @refinement.iterations.sole, :failed?
    assert_equal "Could not connect to Ollama: refused", @refinement.iterations.sole.error
    assert_predicate @refinement.reload, :pending?
  end

  test "does nothing unless the refinement is running" do
    @refinement.update!(status: :pending)

    assert_no_difference -> { PromptRefinementIteration.count } do
      RefinementJob.perform_now(@refinement)
    end
  end

  test "automatically runs subsequent iterations until the target is reached" do
    use_client(evaluation_replies: [ evaluation_reply(verdicts: %w[miss miss]), evaluation_reply(verdicts: %w[match match]) ])

    perform_enqueued_jobs(only: RefinementJob) do
      RefinementJob.perform_now(@refinement, run_to_completion: true)
    end

    assert_equal 2, @refinement.iterations.count
    assert_predicate @refinement.reload, :completed?
    assert_predicate @refinement, :stopped_by_target_reached?
    assert_not_nil @refinement.completed_at
    assert_equal "Briefly explain {{topic}}", @refinement.iterations.last.prompt_revision.template
  end

  test "automatic execution stops at the iteration limit" do
    @refinement.update!(max_iterations: 1)
    use_client(evaluation_replies: [ evaluation_reply(verdicts: %w[miss miss]) ])

    assert_no_enqueued_jobs do
      RefinementJob.perform_now(@refinement, run_to_completion: true)
    end

    assert_predicate @refinement.reload, :completed?
    assert_predicate @refinement, :stopped_by_max_iterations?
  end

  test "automatic execution stops when the teacher reports completion" do
    reply = JSON.parse(evaluation_reply(verdicts: %w[miss miss])).merge("done" => true).to_json
    use_client(evaluation_replies: [ reply ])

    assert_no_enqueued_jobs do
      RefinementJob.perform_now(@refinement, run_to_completion: true)
    end

    assert_predicate @refinement.reload, :stopped_by_converged?
  end

  test "automatic execution pauses after a failed iteration" do
    use_client(evaluation_replies: [], failing_models: [ "teacher:8b" ])

    assert_no_enqueued_jobs do
      RefinementJob.perform_now(@refinement, run_to_completion: true)
    end

    assert_predicate @refinement.reload, :pending?
    assert_predicate @refinement.iterations.sole, :failed?
  end

  private

  def evaluation_reply(verdicts:, prompt: "Briefly explain {{topic}}")
    {
      cases: verdicts.each_with_index.map { |verdict, index| { case: index + 1, verdict: verdict, notes: "Note #{index + 1}" } },
      summary: "Too long.",
      changes: "Asked for brevity.",
      done: false,
      prompt: prompt
    }.to_json
  end

  # Trials answer with the model's role and the prompt; evaluations return the
  # given replies in order, raising any that are errors.
  def use_client(evaluation_replies:, failing_models: [], failing_student_prompts: [])
    evaluations = @evaluations
    client_class = Class.new do
      define_method(:generate) do |model:, prompt:, format: nil, options: nil|
        if format
          evaluations << { model: model, prompt: prompt, format: format, options: options }
          reply = evaluation_replies.fetch(evaluations.size - 1)
          raise reply if reply.is_a?(Exception)

          reply
        else
          failing = failing_models.include?(model) || (model.start_with?("student") && failing_student_prompts.include?(prompt))
          raise Inference::Error, "Generation failed" if failing

          "#{model.start_with?("teacher") ? "Teacher" : "Student"}: #{prompt}"
        end
      end

      define_method(:complete) do |model:, prompt:|
        Inference::Completion.new(content: generate(model: model, prompt: prompt), metrics: {})
      end
    end
    factory = Class.new do
      define_singleton_method(:for) { |_backend, **_options| client_class.new }
    end
    TrialExecutionJob.client_factory = factory
    RefinementJob.client_factory = factory
  end

  def ordered_contents(trial)
    trial.responses.joins(:test_suite_revision_case).order("test_suite_revision_cases.position").map(&:content)
  end
end
