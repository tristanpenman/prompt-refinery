class TrialsController < ApplicationController
  class_attribute :ollama_client_class, default: ::Ollama::Client

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
    @trial = Trial.create_for!(collection: collection, model: attributes[:model])
    TrialExecutionJob.perform_later(@trial)
    redirect_to @trial, notice: "Trial queued."
  rescue ActiveRecord::RecordInvalid => error
    @trial = error.record.is_a?(Trial) ? error.record : Trial.new(attributes)
    load_index_data
    render :index, status: :unprocessable_content
  rescue ActiveRecord::RecordNotFound
    @trial = Trial.new(attributes)
    @trial.errors.add(:collection, "must exist")
    load_index_data
    render :index, status: :unprocessable_content
  end

  private

  def set_trial
    @trial = Trial.find(params[:id])
  end

  def trial_params
    params.expect(trial: %i[collection_id model])
  end

  def load_index_data
    @trials = Trial.includes(:collection, :collection_revision).order(created_at: :desc)
    @collections = Collection.active.with_prompts.order(:name, :id)
    @models = ollama_client_class.new.models.map { |model| model.fetch("name") }
  rescue ::Ollama::Client::Error => error
    @models = []
    @ollama_error = error.message
  end
end
