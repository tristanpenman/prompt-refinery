class Response < ApplicationRecord
  STATUSES = {
    pending: "pending",
    completed: "completed",
    failed: "failed"
  }.freeze

  belongs_to :trial, inverse_of: :responses
  belongs_to :prompt, inverse_of: :responses

  enum :status, STATUSES, validate: true

  validates :prompt_id, uniqueness: { scope: :trial_id }
  validate :prompt_belongs_to_trial_collection

  private

  def prompt_belongs_to_trial_collection
    return unless trial && prompt
    return if trial.collection_id == prompt.collection_id

    errors.add(:prompt, "must belong to the trial's collection")
  end
end
