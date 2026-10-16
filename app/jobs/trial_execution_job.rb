class TrialExecutionJob < ApplicationJob
  queue_as :default

  class_attribute :ollama_client_class, default: ::Ollama::Client

  def perform(trial)
    trial.update!(status: :running, started_at: Time.current)
    client = ollama_client_class.new

    trial.responses
      .joins(:collection_revision_prompt)
      .includes(:collection_revision_prompt)
      .order("collection_revision_prompts.position", "responses.id")
      .each do |response|
      generate_response(client, trial, response)
    end

    status = trial.responses.failed.exists? ? :failed : :completed
    trial.update!(status: status, completed_at: Time.current)
  rescue StandardError => error
    trial.update!(status: :failed, completed_at: Time.current) if trial&.persisted?
    Rails.error.report(error, handled: true)
  end

  private

  def generate_response(client, trial, response)
    content = client.generate(model: trial.model, prompt: response.rendered_prompt)
    response.update!(status: :completed, content: content, error: nil)
  rescue ::Ollama::Client::Error => error
    response.update!(status: :failed, content: nil, error: error.message)
  end
end
