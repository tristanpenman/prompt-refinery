class RefinementsController < ApplicationController
  def index
    @refinement = PromptRefinement.new
    load_index_data
  end

  def show
    @refinement = PromptRefinement
      .includes(:prompt, :starting_prompt_revision, :reference_trial, test_suite_revision: :test_suite_revision_cases,
        iterations: %i[prompt_revision student_trial])
      .find(params[:id])
    # Case evaluations are keyed by test suite revision case id; number them as the trial pages do.
    @case_numbers = @refinement.test_suite_revision.test_suite_revision_cases.each.with_index(1).to_h { |test_case, number| [ test_case.id.to_s, number ] }
  end

  def run
    refinement = PromptRefinement.find(params[:id])
    if refinement.start_iteration!
      if params[:run_to_completion] == "true"
        RefinementJob.perform_later(refinement, run_to_completion: true)
        notice = "Refinement queued to run to completion."
      else
        RefinementJob.perform_later(refinement)
        notice = "Iteration queued."
      end
      redirect_to refinement_path(refinement), notice: notice
    else
      redirect_to refinement_path(refinement), alert: "This refinement can't run another iteration."
    end
  end

  def create
    attributes = refinement_params
    @selected = attributes.slice(:prompt_id, :test_suite_id, :student_language_model_id, :teacher_language_model_id)
    @refinement = PromptRefinement.new(attributes.slice(:max_iterations, :target_agreement, :context_size, :instructions))
    prompt = Prompt.active.find_by(id: attributes[:prompt_id])
    test_suite = TestSuite.active.find_by(id: attributes[:test_suite_id])
    student = available_language_models.find_by(id: attributes[:student_language_model_id])
    teacher = available_language_models.find_by(id: attributes[:teacher_language_model_id])
    @refinement.errors.add(:prompt, "must exist") unless prompt
    @refinement.errors.add(:test_suite, "must exist") unless test_suite
    @refinement.errors.add(:student_model, "must be a model on an enabled backend") unless student
    @refinement.errors.add(:teacher_model, "must be a model on an enabled backend") unless teacher
    return render_index_with_errors if @refinement.errors.any?

    refinement = PromptRefinement.create_for!(
      prompt: prompt,
      test_suite: test_suite,
      student: student,
      teacher: teacher,
      **attributes.slice(:max_iterations, :target_agreement, :context_size, :instructions).to_h.symbolize_keys
    )
    redirect_to refinement_path(refinement), notice: "Refinement created."
  rescue ActiveRecord::RecordInvalid => error
    @refinement.errors.merge!(error.record)
    render_index_with_errors
  end

  private

  def refinement_params
    params.expect(refinement: %i[
      prompt_id test_suite_id student_language_model_id teacher_language_model_id
      max_iterations target_agreement context_size instructions
    ])
  end

  def available_language_models
    LanguageModel.joins(:backend).merge(Backend.enabled)
  end

  def render_index_with_errors
    load_index_data
    render :index, status: :unprocessable_content
  end

  def load_index_data
    @refinements = PromptRefinement
      .includes(:starting_prompt_revision, :test_suite_revision)
      .order(created_at: :desc, id: :desc)
    @prompts = Prompt.active.where.missing(:refinement).order(:name, :id)
    @test_suites = TestSuite.active.joins(:test_cases).distinct.order(:name, :id)
    @model_options = available_language_models
      .includes(:backend)
      .order("backends.system DESC", "backends.name", "language_models.name")
      .group_by(&:backend)
      .to_h { |backend, language_models| [ backend.name, language_models.map { |language_model| [ language_model.name, language_model.id ] } ] }
    @selected ||= {}
  end
end
