class TrialsController < ApplicationController
  class_attribute :ollama_client_class, default: ::Ollama::Client

  before_action :set_trial, only: :show

  def index
    load_index_data
  end

  def show
    @responses = @trial.responses.includes(:prompt).order("prompts.position", "responses.id")
  end

  def create
    @trial = Trial.new(trial_params)

    if create_trial_with_responses
      TrialExecutionJob.perform_later(@trial)
      redirect_to @trial, notice: "Trial queued."
    else
      load_index_data
      render :index, status: :unprocessable_content
    end
  end

  private

  def set_trial
    @trial = Trial.find(params[:id])
  end

  def trial_params
    params.expect(trial: %i[collection_id model])
  end

  def create_trial_with_responses
    Trial.transaction do
      return false unless @trial.save

      @trial.collection.prompts.each do |prompt|
        @trial.responses.create!(prompt: prompt)
      end
    end
    true
  end

  def load_index_data
    @trials = Trial.includes(:collection).order(created_at: :desc)
    @collections = Collection.order(:name, :id)
    @models = ollama_client_class.new.models.map { |model| model.fetch("name") }
  rescue ::Ollama::Client::Error => error
    @models = []
    @ollama_error = error.message
  end
end
