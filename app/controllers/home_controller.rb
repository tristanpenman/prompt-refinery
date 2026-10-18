class HomeController < ApplicationController
  class_attribute :client_factory, default: Inference::Client

  def index
    catalog = Inference::ModelCatalog.new(client_factory:).call
    @models = catalog.models
      .sort_by { |model| model["modified_at"].to_s }
      .reverse
      .first(3)
    @backend_errors = catalog.errors
    load_recent_records
  end

  private

  def load_recent_records
    @collections = Collection.active.order(updated_at: :desc).limit(3)
    @trials = Trial.includes(:collection).order(created_at: :desc).limit(3)
  end
end
