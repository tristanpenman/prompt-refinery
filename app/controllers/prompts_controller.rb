class PromptsController < ApplicationController
  class_attribute :client_factory, default: Inference::Client

  before_action :set_model
  before_action :set_backend

  def show; end

  def create
    @prompt = params[:question].to_s.strip

    if @prompt.blank?
      @error = "Enter a question for the model."
      render_result(status: :unprocessable_content)
      return
    end

    @answer = client_factory.for(@backend).generate(model: @model, prompt: @prompt)
    render_result
  rescue ::Ollama::Client::Error, Inference::Client::UnsupportedAdapter => error
    @error = error.message
    render_result(status: :bad_gateway)
  end

  private

  def set_model
    @model = params[:model].to_s.strip
    redirect_to models_path, alert: "Select a model first." if @model.blank?
  end

  def set_backend
    @backend = if params[:backend_id].present?
      Backend.enabled.find(params[:backend_id])
    else
      Backend.enabled.find_by(system: true) || Backend.enabled.first!
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to models_path, alert: "Select an available model backend."
  end

  def render_result(status: :ok)
    respond_to do |format|
      format.turbo_stream { render :create, status: status }
      format.html { render :show, status: status }
    end
  end
end
