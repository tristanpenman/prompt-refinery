class ModelsController < ApplicationController
  class_attribute :client_factory, default: Inference::Client

  before_action :set_language_model, only: %i[edit update]

  def index
    catalog = Inference::ModelCatalog.new(client_factory:).call
    @models = catalog.models
    @backend_errors = catalog.errors
  end

  def edit
  end

  def update
    if @language_model.update(language_model_params)
      redirect_to models_path, notice: "Model updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def set_language_model
    @language_model = LanguageModel.find(params[:id])
  end

  def language_model_params
    params.expect(language_model: [ :language_model_family_name ])
  end
end
