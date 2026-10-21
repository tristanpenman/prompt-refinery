require "test_helper"

class PromptRefinementTest < ActiveSupport::TestCase
  setup do
    @backend = Backend.ensure_system_default!
    @prompt = create_prompt(template: "Explain {{topic}}")
    @test_suite = create_test_suite
  end

  test "defaults to a pending refinement with the default instructions" do
    refinement = create_refinement

    assert_predicate refinement, :pending?
    assert_nil refinement.stop_reason
    assert_equal 3, refinement.max_iterations
    assert_equal 1, refinement.target_agreement
    assert_equal 16_384, refinement.context_size
    assert_equal PromptRefinement.default_instructions, refinement.instructions
    assert_includes refinement.instructions, "{{current_prompt}}"
  end

  test "copies the student and teacher backends" do
    teacher_backend = Backend.create!(name: "GPU server", base_url: "http://gpu.test:11434")

    refinement = create_refinement(teacher_backend: teacher_backend)

    assert_equal "Local Ollama", refinement.student_backend_name
    assert_equal @backend.base_url, refinement.student_backend_base_url
    assert_equal "GPU server", refinement.teacher_backend_name
    assert_equal "http://gpu.test:11434", refinement.teacher_backend_base_url
  end

  test "requires its inputs, models, and a valid status" do
    refinement = PromptRefinement.new(name: "", status: "unknown")

    assert_not refinement.valid?
    assert_includes refinement.errors[:prompt], "must exist"
    assert_includes refinement.errors[:starting_prompt_revision], "must exist"
    assert_includes refinement.errors[:test_suite_revision], "must exist"
    assert_includes refinement.errors[:student_backend], "must exist"
    assert_includes refinement.errors[:teacher_backend], "must exist"
    assert_includes refinement.errors[:name], "can't be blank"
    assert_includes refinement.errors[:student_model], "can't be blank"
    assert_includes refinement.errors[:teacher_model], "can't be blank"
    assert_includes refinement.errors[:status], "is not included in the list"
  end

  test "limits the stopping rules" do
    refinement = build_refinement(max_iterations: 11, target_agreement: 1.5, context_size: 0)

    assert_not refinement.valid?
    assert_includes refinement.errors[:max_iterations], "must be in 1..10"
    assert_includes refinement.errors[:target_agreement], "must be in 0..1"
    assert_includes refinement.errors[:context_size], "must be greater than 0"
  end

  test "records why it stopped" do
    refinement = create_refinement
    refinement.update!(status: :stopped, stop_reason: :converged)

    assert_predicate refinement, :stopped_by_converged?
    assert_not build_refinement(stop_reason: "bored").valid?
  end

  test "instructions may only use the evaluator variables" do
    refinement = build_refinement(instructions: "Improve {{current_prompt}} for {{audience}} and {{tone}}")

    assert_not refinement.valid?
    assert_includes refinement.errors[:instructions],
      "use unknown variables audience and tone; available variables are current_prompt, variables, cases, and history"
  end

  test "works on a separate prompt from the one being refined" do
    refinement = build_refinement(prompt: @prompt)

    assert_not refinement.valid?
    assert_includes refinement.errors[:prompt], "must be a separate working prompt, not the prompt being refined"
  end

  test "cannot be created for an archived prompt or test suite" do
    refinement = build_refinement
    @prompt.archive!
    @test_suite.archive!

    assert_not refinement.valid?
    assert_includes refinement.errors[:starting_prompt_revision], "belongs to an archived prompt"
    assert_includes refinement.errors[:test_suite_revision], "belongs to an archived test suite"
  end

  test "requires a test suite with test cases that provide the prompt's variables" do
    empty_suite = TestSuite.create!(name: "Empty", variables: [ "audience" ])
    refinement = build_refinement(test_suite_revision: TestSuiteRevision.capture!(empty_suite))

    assert_not refinement.valid?
    assert_includes refinement.errors[:test_suite_revision], "must contain at least one test case"
    assert_includes refinement.errors[:test_suite_revision], "does not provide variable used by the prompt: topic"
  end

  test "requires enabled backends" do
    disabled = Backend.create!(name: "Old server", base_url: "http://old.test:11434", enabled: false)

    refinement = build_refinement(student_backend: disabled, teacher_backend: disabled)

    assert_not refinement.valid?
    assert_includes refinement.errors[:student_backend], "must be enabled"
    assert_includes refinement.errors[:teacher_backend], "must be enabled"
  end

  test "fixes its inputs once created but allows more iterations" do
    refinement = create_refinement

    assert_not refinement.update(teacher_model: "llama3.2:3b", instructions: "Do better: {{current_prompt}}")
    assert_includes refinement.errors[:base], "Teacher model and Instructions cannot be changed after the refinement is created"

    refinement.reload
    assert refinement.update(max_iterations: 5)
  end

  test "the reference trial runs the teacher on the starting revisions" do
    refinement = create_refinement
    student_trial = Trial.create!(
      prompt_revision: refinement.starting_prompt_revision,
      test_suite_revision: refinement.test_suite_revision,
      backend: @backend,
      model: refinement.student_model
    )

    assert_not refinement.update(reference_trial: student_trial)
    assert_includes refinement.errors[:reference_trial],
      "must run the teacher model on the starting prompt revision and test suite revision"

    reference_trial = Trial.create!(
      prompt_revision: refinement.starting_prompt_revision,
      test_suite_revision: refinement.test_suite_revision,
      backend: @backend,
      model: refinement.teacher_model
    )
    refinement.reload
    assert refinement.update(reference_trial: reference_trial)
    assert_equal refinement, reference_trial.reload.reference_refinement
  end

  test "lists iterations in order and destroys them with the refinement" do
    refinement = create_refinement
    revision = PromptRevision.capture!(refinement.prompt)
    second = refinement.iterations.create!(number: 2, prompt_revision: revision)
    first = refinement.iterations.create!(number: 1, prompt_revision: revision)

    assert_equal [ first, second ], refinement.iterations.reload.to_a

    assert_difference -> { PromptRefinementIteration.count }, -2 do
      refinement.destroy!
    end
  end

  test "prevents the records it depends on from being deleted" do
    refinement = create_refinement

    assert_not refinement.prompt.destroy
    assert_not refinement.starting_prompt_revision.destroy
    assert PromptRefinement.exists?(refinement.id)
  end

  private

  def build_refinement(**attributes)
    PromptRefinement.new({
      name: "Explain",
      prompt: Prompt.create!(name: "Explain (refinement)", template: @prompt.template),
      starting_prompt_revision: PromptRevision.capture!(@prompt),
      test_suite_revision: TestSuiteRevision.capture!(@test_suite),
      student_backend: @backend,
      student_model: "llama3.2:3b",
      teacher_backend: @backend,
      teacher_model: "qwen2.5:7b"
    }.merge(attributes))
  end

  def create_refinement(**attributes)
    build_refinement(**attributes).tap(&:save!)
  end
end
