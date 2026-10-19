class SettingsController < ApplicationController
  class_attribute :client_factory, default: Inference::Client

  def index
    catalog = Inference::ModelCatalog.new(client_factory:).call
    @models = catalog.models
      .sort_by { |model| model["modified_at"].to_s }
      .reverse
      .first(3)
    @backend_errors = catalog.errors
    @backends = Backend.order(system: :desc, name: :asc, id: :asc)
    @language_model_families = LanguageModelFamily
      .left_joins(:language_models)
      .group(:id)
      .select("language_model_families.*, COUNT(language_models.id) AS language_models_count")
      .order(:name)
  end
end
