module Settings
  class BackendsController < ApplicationController
    class_attribute :client_factory, default: Inference::Client

    before_action :set_backend, only: %i[edit update destroy test_connection]

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

    def edit
    end

    def update
      if @backend.update(editable_backend_params)
        redirect_to settings_backends_path, notice: "Backend updated."
      else
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      if @backend.destroy
        redirect_to settings_backends_path, notice: "Backend deleted."
      else
        redirect_to settings_backends_path, alert: @backend.errors.full_messages.to_sentence
      end
    end

    def test_connection
      models = client_factory.for(@backend).models
      unless models.is_a?(Array) && models.all? { |model| model.is_a?(Hash) && model["name"].present? }
        raise Inference::Error, "the server returned an invalid model list"
      end

      notice = "Connected to #{@backend.name}. Found #{helpers.pluralize(models.size, "model")}."
      notice += " Discovery does not verify invocation access." if @backend.bedrock?
      redirect_to settings_backends_path, notice:

    rescue Inference::Error => error
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
      params.expect(backend: %i[name base_url adapter enabled])
    end

    def editable_backend_params
      return params.expect(backend: [ :enabled ]) if @backend.system?

      backend_params
    end
  end
end
