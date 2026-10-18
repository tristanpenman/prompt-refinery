module Settings
  class BackendsController < ApplicationController
    class_attribute :client_factory, default: Inference::Client

    before_action :set_backend, only: :test_connection

    def index
      prepare_index
    end

    def create
      @backend = Backend.new(backend_params)

      if @backend.save
        redirect_to settings_backends_path, notice: "Backend created."
      else
        load_backends
        render :index, status: :unprocessable_content
      end
    end

    def test_connection
      models = client_factory.for(@backend).models
      unless models.is_a?(Array) && models.all? { |model| model.is_a?(Hash) && model["name"].present? }
        raise Ollama::Client::Error, "the server returned an invalid model list"
      end

      redirect_to settings_backends_path,
        notice: "Connected to #{@backend.name}. Found #{helpers.pluralize(models.size, "model")}."
    rescue Ollama::Client::Error, Inference::Client::UnsupportedAdapter => error
      redirect_to settings_backends_path,
        alert: "Could not connect to #{@backend.name}: #{error.message}"
    end

    private

    def set_backend
      @backend = Backend.find(params[:id])
    end

    def prepare_index
      load_backends
      @backend = Backend.new
    end

    def load_backends
      @backends = Backend.order(system: :desc, name: :asc, id: :asc)
    end

    def backend_params
      params.expect(backend: %i[name base_url])
    end
  end
end
