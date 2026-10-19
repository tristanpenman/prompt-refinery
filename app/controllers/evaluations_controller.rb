class EvaluationsController < ApplicationController
  class_attribute :client_factory, default: Inference::Client

  before_action :set_model
  before_action :set_backend
  before_action :set_collections

  def show; end

  def create
    @collection = Collection.find(params[:collection_id])
    client = client_factory.for(@backend)
    @results = @collection.prompts.map do |prompt|
      evaluate_prompt(client, prompt)
    end

    render_results
  rescue ActiveRecord::RecordNotFound
    @error = "Choose an available collection."
    render_results(status: :unprocessable_content)
  end

  private

  def set_model
    @model = params[:model].to_s.strip
    redirect_to settings_models_path, alert: "Select a model first." if @model.blank?
  end

  def set_backend
    @backend = if params[:backend_id].present?
      Backend.enabled.find(params[:backend_id])
    else
      Backend.enabled.find_by(system: true) || Backend.enabled.first!
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to settings_models_path, alert: "Select an available model backend."
  end

  def set_collections
    @collections = Collection.order(:name, :id)
  end

  def evaluate_prompt(client, prompt)
    {
      prompt: prompt,
      response: client.generate(model: @model, prompt: prompt.template)
    }
  rescue ::Ollama::Client::Error => error
    { prompt: prompt, error: error.message }
  end

  def render_results(status: :ok)
    respond_to do |format|
      format.turbo_stream { render :create, status: status }
      format.html { render :show, status: status }
    end
  end
end
