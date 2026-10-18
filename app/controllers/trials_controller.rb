class TrialsController < ApplicationController
  class_attribute :client_factory, default: Inference::Client

  before_action :set_trial, only: :show

  def index
    load_index_data
  end

  def show
    @responses = @trial.responses
      .joins(:collection_revision_prompt)
      .includes(collection_revision_prompt: :prompt_revision)
      .order("collection_revision_prompts.position", "responses.id")
  end

  def create
    attributes = trial_params
    collection = Collection.active.find(attributes[:collection_id])
    backend = Backend.enabled.find(attributes[:backend_id])
    @trial = Trial.create_for!(collection: collection, backend: backend, model: attributes[:model])
    TrialExecutionJob.perform_later(@trial)
    redirect_to @trial, notice: "Trial queued."
  rescue ActiveRecord::RecordInvalid => error
    @trial = error.record.is_a?(Trial) ? error.record : Trial.new(attributes)
    load_index_data
    render :index, status: :unprocessable_content
  rescue ActiveRecord::RecordNotFound
    @trial = Trial.new(attributes)
    if Collection.active.exists?(attributes[:collection_id])
      @trial.errors.add(:backend, "must exist and be enabled")
    else
      @trial.errors.add(:collection, "must exist")
    end
    load_index_data
    render :index, status: :unprocessable_content
  end

  private

  def set_trial
    @trial = Trial.find(params[:id])
  end

  def trial_params
    params.expect(trial: %i[collection_id backend_id model])
  end

  def load_index_data
    @trials = Trial.includes(:collection, :collection_revision, :backend).order(created_at: :desc)
    @collections = Collection.active.with_prompts.order(:name, :id)
    @backends = Backend.enabled.order(system: :desc, name: :asc, id: :asc)
    requested_backend_id = params[:backend_id] || @trial&.backend_id
    @selected_backend = @backends.find { |backend| backend.id == requested_backend_id.to_i } || @backends.first
    @models = @selected_backend ? client_factory.for(@selected_backend).models.map { |model| model.fetch("name") } : []
  rescue ::Ollama::Client::Error => error
    @models = []
    @ollama_error = error.message
  end
end
