module Inference
  class ModelCatalog
    Result = Data.define(:models, :errors)
    Error = Data.define(:backend, :message)

    def initialize(backends: Backend.enabled.order(system: :desc, name: :asc, id: :asc), client_factory: Inference::Client)
      @backends = backends
      @client_factory = client_factory
    end

    def call
      models = []
      errors = []

      backends.each do |backend|
        backend_models = client_factory.for(backend).models
        models.concat(backend_models.map { |model| model.merge("backend" => backend) })
      rescue Ollama::Client::Error, Inference::Client::UnsupportedAdapter => error
        errors << Error.new(backend:, message: error.message)
      end

      Result.new(models:, errors:)
    end

    private

    attr_reader :backends, :client_factory
  end
end
