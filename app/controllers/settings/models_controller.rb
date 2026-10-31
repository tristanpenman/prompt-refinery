module Settings
  class ModelsController < ApplicationController
    class_attribute :client_factory, default: Inference::Client

    before_action :set_language_model, only: %i[edit update]

    def index
      @families = LanguageModelFamily.where(id: LanguageModel.select(:language_model_family_id)).order(:name)
      @family = @families.find_by(id: params[:family])
      language_models = LanguageModel
        .includes(:backend, :language_model_family)
        .joins(:backend)
        .order("backends.system DESC", "backends.name", "language_models.name", "language_models.id")
      language_models = language_models.where(language_model_family: @family) if @family
      @available_models, @unavailable_models = language_models.partition(&:available?)
    end

    def refresh
      backend_count = Backend.enabled.count
      if backend_count.zero?
        redirect_to settings_models_path, alert: "There are no enabled backends to check."
        return
      end

      catalog = Inference::ModelCatalog.new(client_factory:).call
      flash[:notice] = refresh_summary(catalog, backend_count - catalog.errors.size)
      if catalog.errors.any?
        flash[:alert] = catalog.errors.map { |error| "Could not check #{error.backend.name}: #{error.message}" }.join(" ")
      end
      redirect_to settings_models_path
    end

    def edit
    end

    def update
      if @language_model.update(language_model_params)
        redirect_to settings_models_path, notice: "Model updated."
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

    def refresh_summary(catalog, checked_count)
      summary = "Checked #{helpers.pluralize(checked_count, "backend")} and found #{helpers.pluralize(catalog.models.size, "model")}"
      new_count = catalog.new_models.size
      new_count.positive? ? "#{summary}, including #{new_count} new." : "#{summary}. No new models."
    end
  end
end
