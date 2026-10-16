class HomeController < ApplicationController
  class_attribute :ollama_client_class, default: ::Ollama::Client

  def index
    @models = ollama_client_class.new.models
  rescue ::Ollama::Client::Error => error
    @models = []
    @ollama_error = error.message
  end
end
