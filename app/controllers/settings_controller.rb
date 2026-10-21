class SettingsController < ApplicationController
  def index
    @language_models = LanguageModel.includes(:backend).order(refreshed_at: :desc, id: :desc).limit(3)
    @more_language_models_count = [ LanguageModel.count - @language_models.size, 0 ].max
    @backends = Backend.order(system: :desc, name: :asc, id: :asc)
    @language_model_families = LanguageModelFamily
      .left_joins(:language_models)
      .group(:id)
      .select("language_model_families.*, COUNT(language_models.id) AS language_models_count")
      .order(:name)
  end
end
