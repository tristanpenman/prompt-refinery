class EvaluationsController < ApplicationController
  class_attribute :ollama_client_class, default: ::Ollama::Client

  before_action :set_model
  before_action :set_collections

  def show; end

  def create
    @collection = Collection.find(params[:collection_id])
    client = ollama_client_class.new
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
    redirect_to root_path, alert: "Select a model first." if @model.blank?
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
