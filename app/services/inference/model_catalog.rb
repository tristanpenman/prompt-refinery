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
        mark_missing_unavailable(backend, backend_models)
      rescue Inference::Error => error
        errors << Error.new(backend:, message: error.message)
      end

      Result.new(models:, errors:, new_models:)
    end

    private

    attr_reader :backends, :client_factory

    # Creates a record for a newly discovered model, keeps the size and
    # details current, and records when the model was last seen and that it is
    # available. The family is
    # only derived for new records, so a family chosen in settings is kept.
    def record(backend, model)
      return if model["name"].blank?

      language_model = backend.language_models.find_or_initialize_by(name: model["name"])
      language_model.assign_attributes(
        size: model["size"],
        details: model["details"].presence || {},
        refreshed_at: Time.current,
        available: true
      )
      language_model if language_model.save
    end

    # Models are only marked unavailable for backends that were checked, so a
    # backend that couldn't be reached leaves its models as they were.
    def mark_missing_unavailable(backend, backend_models)
      backend.language_models
        .where(available: true)
        .where.not(name: backend_models.map { |model| model["name"] })
        .update_all(available: false, updated_at: Time.current)
    end
  end
end
