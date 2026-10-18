class ModelsController < ApplicationController
  class_attribute :client_factory, default: Inference::Client

  def index
    catalog = Inference::ModelCatalog.new(client_factory:).call
    @models = catalog.models
    @backend_errors = catalog.errors
  end
end
