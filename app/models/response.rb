# == Schema Information
#
# Table name: responses
# Database name: primary
#
#  id                          :integer          not null, primary key
#  content                     :text
#  error                       :text
#  eval_count                  :integer
#  eval_duration               :bigint
#  load_duration               :bigint
#  prompt_eval_count           :integer
#  prompt_eval_duration        :bigint
#  rendered_prompt             :text             not null
#  status                      :string           default("pending"), not null
#  total_duration              :bigint
#  created_at                  :datetime         not null
#  updated_at                  :datetime         not null
#  test_suite_revision_case_id :integer          not null
#  trial_id                    :integer          not null
#
# Indexes
#
#  index_responses_on_test_suite_revision_case_id  (test_suite_revision_case_id)
#  index_responses_on_trial_and_revision_case      (trial_id,test_suite_revision_case_id) UNIQUE
#  index_responses_on_trial_id                     (trial_id)
#
# Foreign Keys
#
#  test_suite_revision_case_id  (test_suite_revision_case_id => test_suite_revision_cases.id)
#  trial_id                     (trial_id => trials.id)
#
class Response < ApplicationRecord
  STATUSES = {
    pending: "pending",
    completed: "completed",
    failed: "failed"
  }.freeze

  belongs_to :trial, inverse_of: :responses
  belongs_to :test_suite_revision_case, inverse_of: :responses
  has_one :test_case_revision, through: :test_suite_revision_case

  enum :status, STATUSES, validate: true

  validates :test_suite_revision_case_id, uniqueness: { scope: :trial_id }
  validates :rendered_prompt, presence: true
  validate :revision_case_belongs_to_trial_revision

  # Generation speed in tokens per second, excluding prompt processing.
  def tokens_per_second
    return unless eval_count && eval_duration&.positive?

    eval_count / (eval_duration / 1_000_000_000.0)
  end

  private

  def revision_case_belongs_to_trial_revision
    return unless trial && test_suite_revision_case
    return if test_suite_revision_case.test_suite_revision_id == trial.test_suite_revision_id

    errors.add(:test_suite_revision_case, "must belong to the trial's test suite revision")
  end
end
