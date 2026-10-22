# Runs one iteration of a refinement that was started with
# PromptRefinement#start_iteration!, then returns the refinement to pending.
class RefinementJob < ApplicationJob
  queue_as :default

  # A failure that ends the iteration, with a message to show on it.
  IterationFailed = Class.new(StandardError)

  class_attribute :client_factory, default: Inference::Client

  def perform(refinement)
    return unless refinement.running?

    iteration = refinement.iterations.create!(
      number: refinement.iterations.maximum(:number).to_i + 1,
      prompt_revision: PromptRevision.capture!(refinement.prompt),
      status: :running_trial,
      started_at: Time.current
    )
    run_iteration(refinement, iteration)
  rescue IterationFailed, ::Ollama::Client::Error, Inference::Client::UnsupportedAdapter => error
    iteration&.update!(status: :failed, error: error.message, completed_at: Time.current)
  rescue StandardError => error
    iteration&.update!(status: :failed, error: "Unexpected error: #{error.message}", completed_at: Time.current) unless iteration&.completed?
    Rails.error.report(error, handled: true)
  ensure
    refinement.update!(status: :pending) if refinement.reload.running?
  end

  private

  def run_iteration(refinement, iteration)
    ensure_reference_trial(refinement)

    student_trial = run_trial(refinement, iteration.prompt_revision, refinement.student_backend, refinement.student_model)
    iteration.update!(student_trial: student_trial, status: :evaluating)
    if student_trial.responses.completed.none?
      raise IterationFailed, "Every response in the student trial (##{student_trial.id}) failed."
    end

    result = evaluate(refinement, iteration)
    iteration.update!(
      status: :completed,
      completed_at: Time.current,
      agreement: result.agreement,
      case_evaluations: result.case_evaluations,
      summary: result.summary,
      change_summary: result.change_summary,
      proposed_template: result.proposed_template
    )
    # The next iteration captures the proposed prompt as a new revision.
    refinement.prompt.update!(template: result.proposed_template)
  end

  # The teacher's outputs for the starting prompt are the target for every
  # iteration, so they're only generated once.
  def ensure_reference_trial(refinement)
    return if refinement.reference_trial

    trial = run_trial(refinement, refinement.starting_prompt_revision, refinement.teacher_backend, refinement.teacher_model)
    raise IterationFailed, "The reference trial (##{trial.id}) failed, so there is nothing to compare with." unless trial.completed?

    refinement.update!(reference_trial: trial)
  end

  def run_trial(refinement, prompt_revision, backend, model)
    trial = Trial.create_from_revisions!(
      prompt_revision: prompt_revision,
      test_suite_revision: refinement.test_suite_revision,
      backend: backend,
      model: model
    )
    TrialExecutionJob.perform_now(trial)
    trial.reload
  end

  # Asks the teacher to evaluate the student trial. A rejected reply is retried
  # once, with the reason added to the request.
  def evaluate(refinement, iteration)
    evaluation = RefinementEvaluation.new(refinement: refinement, iteration: iteration)
    client = client_factory.for(refinement.teacher_backend)
    prompt = evaluation.prompt

    2.times do |attempt|
      reply = client.generate(
        model: refinement.teacher_model,
        prompt: prompt,
        format: RefinementEvaluation::FORMAT,
        options: { temperature: 0, num_ctx: refinement.context_size }
      )
      iteration.update!(evaluation_prompt: prompt, evaluation_response: reply)
      return evaluation.parse(reply)
    rescue RefinementEvaluation::Invalid => error
      raise IterationFailed, "The teacher's evaluation was rejected twice: #{error.message}." if attempt == 1

      prompt = evaluation.retry_prompt(error.message)
    end
  end
end
