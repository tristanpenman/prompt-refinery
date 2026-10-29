class TrialExecutionJob < ApplicationJob
  queue_as :default

  class_attribute :client_factory, default: Inference::Client

  def perform(trial)
    trial.update!(status: :running, started_at: Time.current)
    client = client_factory.for(trial.backend, base_url: trial.backend_base_url)

    trial.responses
      .joins(:test_suite_revision_case)
      .order("test_suite_revision_cases.position", "responses.id")
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
    completion = client.complete(model: trial.model, prompt: response.rendered_prompt)
    response.update!(status: :completed, content: completion.content, error: nil, **completion.metrics)
  rescue Inference::Error => error
    response.update!(status: :failed, content: nil, error: error.message)
  end
end
