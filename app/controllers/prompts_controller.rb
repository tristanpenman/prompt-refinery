class PromptsController < ApplicationController
  class_attribute :ollama_client_class, default: ::Ollama::Client

  before_action :set_model

  def show; end

  def create
    @prompt = params[:question].to_s.strip

    if @prompt.blank?
      @error = "Enter a question for the model."
      render_result(status: :unprocessable_content)
      return
    end

    @answer = ollama_client_class.new.generate(model: @model, prompt: @prompt)
    render_result
  rescue ::Ollama::Client::Error => error
    @error = error.message
    render_result(status: :bad_gateway)
  end

  private

  def set_model
    @model = params[:model].to_s.strip
    redirect_to root_path, alert: "Select a model first." if @model.blank?
  end

  def render_result(status: :ok)
    respond_to do |format|
      format.turbo_stream { render :create, status: status }
      format.html { render :show, status: status }
    end
  end
end
