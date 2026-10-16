class HomeController < ApplicationController
  class_attribute :ollama_client_class, default: ::Ollama::Client

  def index
    @models = ollama_client_class.new.models
      .sort_by { |model| model["modified_at"].to_s }
      .reverse
      .first(3)
    load_recent_records
  rescue ::Ollama::Client::Error => error
    @models = []
    @ollama_error = error.message
    load_recent_records
  end

  private

  def load_recent_records
    @collections = Collection.order(updated_at: :desc).limit(3)
    @trials = Trial.includes(:collection).order(created_at: :desc).limit(3)
  end
end
