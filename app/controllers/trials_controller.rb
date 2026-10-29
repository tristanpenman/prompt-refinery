class TrialsController < ApplicationController
  class_attribute :client_factory, default: Inference::Client

  before_action :set_trial, only: :show

  def index
    load_index_data
  end

  def show
    @responses = @trial.responses
      .joins(:test_suite_revision_case)
      .includes(test_suite_revision_case: :test_case_revision)
      .order("test_suite_revision_cases.position", "responses.id")
  end

  def create
    attributes = trial_params
    @trial = Trial.new(attributes.slice(:backend_id, :model))
    @selected_prompt_id = attributes[:prompt_id]
    @selected_test_suite_id = attributes[:test_suite_id]
    prompt = available_prompts.find_by(id: attributes[:prompt_id])
    test_suite = available_test_suites.find_by(id: attributes[:test_suite_id])
    backend = Backend.enabled.find_by(id: attributes[:backend_id])
    @trial.errors.add(:prompt, "must exist") unless prompt
    @trial.errors.add(:test_suite, "must exist") unless test_suite
    @trial.errors.add(:backend, "must exist and be enabled") unless backend
    return render_index_with_errors if @trial.errors.any?

    @trial = Trial.create_for!(prompt: prompt, test_suite: test_suite, backend: backend, model: attributes[:model])
    TrialExecutionJob.perform_later(@trial)
    redirect_to @trial, notice: "Trial queued."
  rescue ActiveRecord::RecordInvalid => error
    if error.record.is_a?(Trial)
      @trial = error.record
    else
      @trial.errors.merge!(error.record)
    end
    render_index_with_errors
  end

  private

  def set_trial
    @trial = Trial.find(params[:id])
  end

  def trial_params
    params.expect(trial: %i[prompt_id test_suite_id backend_id model])
  end

  def available_prompts
    Prompt.active
  end

  def available_test_suites
    TestSuite.active
  end

  def render_index_with_errors
    load_index_data
    render :index, status: :unprocessable_content
  end

  def load_index_data
    @trials = Trial.includes(:prompt_revision, :test_suite_revision).order(created_at: :desc)
    @prompts = available_prompts.order(:name, :id)
    @test_suites = available_test_suites.joins(:test_cases).distinct.order(:name, :id)
    @backends = Backend.enabled.order(system: :desc, name: :asc, id: :asc)
    requested_backend_id = params[:backend_id] || @trial&.backend_id
    @selected_backend = @backends.find { |backend| backend.id == requested_backend_id.to_i } || @backends.first
    @models = @selected_backend ? client_factory.for(@selected_backend).models.map { |model| model.fetch("name") } : []
  rescue Inference::Error => error
    @models = []
    @ollama_error = error.message
  end
end
