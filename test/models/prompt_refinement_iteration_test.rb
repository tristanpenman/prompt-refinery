require "test_helper"

class PromptRefinementIterationTest < ActiveSupport::TestCase
  setup do
    @backend = Backend.ensure_system_default!
    prompt = create_prompt(template: "Explain {{topic}}")
    @test_suite_revision = TestSuiteRevision.capture!(create_test_suite)
    @refinement = PromptRefinement.create!(
      name: "Explain",
      prompt: Prompt.create!(name: "Explain (refinement)", template: prompt.template),
      starting_prompt_revision: PromptRevision.capture!(prompt),
      test_suite_revision: @test_suite_revision,
      student_backend: @backend,
      student_model: "llama3.2:3b",
      teacher_backend: @backend,
      teacher_model: "qwen2.5:7b"
    )
    @revision = PromptRevision.capture!(@refinement.prompt)
  end

  test "defaults to a pending iteration without an evaluation" do
    iteration = @refinement.iterations.create!(number: 1, prompt_revision: @revision)

    assert_predicate iteration, :pending?
    assert_equal({}, iteration.case_evaluations)
    assert_nil iteration.agreement
    assert_nil iteration.student_trial
  end

  test "is numbered once per refinement" do
    @refinement.iterations.create!(number: 1, prompt_revision: @revision)

    iteration = @refinement.iterations.build(number: 1, prompt_revision: @revision)
    assert_not iteration.valid?
    assert_includes iteration.errors[:number], "has already been taken"

    assert_not @refinement.iterations.build(number: 0, prompt_revision: @revision).valid?
  end

  test "runs a revision of the working prompt" do
    iteration = @refinement.iterations.build(number: 1, prompt_revision: @refinement.starting_prompt_revision)

    assert_not iteration.valid?
    assert_includes iteration.errors[:prompt_revision], "must be a revision of the refinement's working prompt"
  end

  test "the student trial runs the student model on the iteration's revision" do
    iteration = @refinement.iterations.create!(number: 1, prompt_revision: @revision)

    assert_not iteration.update(student_trial: trial_for(@refinement.teacher_model))
    assert_includes iteration.errors[:student_trial],
      "must run the student model on this iteration's prompt revision and the refinement's test suite revision"

    trial = trial_for(@refinement.student_model)
    assert iteration.reload.update(student_trial: trial)
    assert_equal iteration, trial.reload.refinement_iteration
  end

  test "stores a verdict and notes for each test case" do
    case_id = @test_suite_revision.test_suite_revision_cases.first.id
    iteration = @refinement.iterations.create!(
      number: 1,
      prompt_revision: @revision,
      case_evaluations: { case_id.to_s => { "verdict" => "partial", "notes" => "Too long." } },
      agreement: 0.5
    )

    assert_equal({ "verdict" => "partial", "notes" => "Too long." }, iteration.reload.case_evaluations[case_id.to_s])
    assert_equal 0.5, iteration.agreement
  end

  test "rejects malformed verdicts and agreement outside 0 to 1" do
    iteration = @refinement.iterations.build(
      number: 1,
      prompt_revision: @revision,
      case_evaluations: { "1" => { "verdict" => "close enough" } },
      agreement: 1.2
    )

    assert_not iteration.valid?
    assert_includes iteration.errors[:case_evaluations],
      "must map test case ids to a verdict of match, partial, or miss and optional notes"
    assert_includes iteration.errors[:agreement], "must be in 0..1"
  end

  test "cannot change once completed" do
    iteration = @refinement.iterations.create!(number: 1, prompt_revision: @revision)
    iteration.update!(status: :completed, summary: "Close enough.")

    assert_not iteration.update(summary: "Changed")
    assert_includes iteration.errors[:base], "Completed refinement iterations are immutable"
    assert_equal "Close enough.", iteration.reload.summary
  end

  test "prevents its trial and revision from being deleted" do
    trial = trial_for(@refinement.student_model)
    @refinement.iterations.create!(number: 1, prompt_revision: @revision, student_trial: trial)

    assert_not trial.destroy
    assert_not @revision.destroy
  end

  private

  def trial_for(model)
    Trial.create!(prompt_revision: @revision, test_suite_revision: @test_suite_revision, backend: @backend, model: model)
  end
end
