module Inference
  class ModelCatalog
    Result = Data.define(:models, :errors, :new_models)
    Error = Data.define(:backend, :message)

    def initialize(backends: Backend.enabled.order(system: :desc, name: :asc, id: :asc), client_factory: Inference::Client)
      @backends = backends
      @client_factory = client_factory
    end

    def call
      models = []
      errors = []
      new_models = []

      backends.each do |backend|
        backend_models = client_factory.for(backend).models
        models.concat(backend_models.map do |model|
          language_model = record(backend, model)
          new_models << language_model if language_model&.previously_new_record?
          model.merge("backend" => backend, "language_model" => language_model)
        end)
      rescue Ollama::Client::Error, Inference::Client::UnsupportedAdapter => error
        errors << Error.new(backend:, message: error.message)
      end

      Result.new(models:, errors:, new_models:)
    end

    private

    attr_reader :backends, :client_factory

    # Creates a record for a newly discovered model and keeps the size and
    # details current. The family is only derived for new records, so a family
    # chosen in settings is kept.
    def record(backend, model)
      return if model["name"].blank?

      language_model = backend.language_models.find_or_initialize_by(name: model["name"])
      language_model.assign_attributes(size: model["size"], details: model["details"].presence || {})
      language_model if language_model.save
    end
  end
end
