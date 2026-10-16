# == Schema Information
#
# Table name: responses
# Database name: primary
#
#  id                            :integer          not null, primary key
#  content                       :text
#  error                         :text
#  rendered_prompt               :text             not null
#  status                        :string           default("pending"), not null
#  created_at                    :datetime         not null
#  updated_at                    :datetime         not null
#  collection_revision_prompt_id :integer          not null
#  prompt_id                     :integer          not null
#  trial_id                      :integer          not null
#
# Indexes
#
#  index_responses_on_collection_revision_prompt_id  (collection_revision_prompt_id)
#  index_responses_on_prompt_id                      (prompt_id)
#  index_responses_on_trial_and_revision_prompt      (trial_id,collection_revision_prompt_id) UNIQUE
#  index_responses_on_trial_id                       (trial_id)
#  index_responses_on_trial_id_and_prompt_id         (trial_id,prompt_id) UNIQUE
#
# Foreign Keys
#
#  collection_revision_prompt_id  (collection_revision_prompt_id => collection_revision_prompts.id)
#  prompt_id                      (prompt_id => prompts.id)
#  trial_id                       (trial_id => trials.id)
#
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
