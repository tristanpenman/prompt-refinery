class Response < ApplicationRecord
  STATUSES = {
    pending: "pending",
    completed: "completed",
    failed: "failed"
  }.freeze

  belongs_to :trial, inverse_of: :responses
  belongs_to :prompt, inverse_of: :responses
  belongs_to :collection_revision_prompt, inverse_of: :responses

  enum :status, STATUSES, validate: true

  validates :prompt_id, uniqueness: { scope: :trial_id }
  validates :collection_revision_prompt_id, uniqueness: { scope: :trial_id }
  validates :rendered_prompt, presence: true
  validate :prompt_belongs_to_trial_collection
  validate :revision_prompt_belongs_to_trial_revision

  private

  def prompt_belongs_to_trial_collection
    return unless trial && prompt
    return if trial.collection_id == prompt.collection_id

    errors.add(:prompt, "must belong to the trial's collection")
  end

  def revision_prompt_belongs_to_trial_revision
    return unless trial && collection_revision_prompt
    return if collection_revision_prompt.collection_revision_id == trial.collection_revision_id

    errors.add(:collection_revision_prompt, "must belong to the trial's collection revision")
  end
end
