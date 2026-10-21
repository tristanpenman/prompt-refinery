# == Schema Information
#
# Table name: prompt_refinement_iterations
# Database name: primary
#
#  id                  :integer          not null, primary key
#  agreement           :decimal(4, 3)
#  case_evaluations    :json             not null
#  change_summary      :text
#  completed_at        :datetime
#  error               :text
#  evaluation_prompt   :text
#  evaluation_response :text
#  number              :integer          not null
#  proposed_template   :text
#  started_at          :datetime
#  status              :string           default("pending"), not null
#  summary             :text
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  prompt_revision_id  :integer          not null
#  refinement_id       :integer          not null
#  student_trial_id    :integer
#
# Indexes
#
#  index_prompt_refinement_iterations_on_prompt_revision_id        (prompt_revision_id)
#  index_prompt_refinement_iterations_on_refinement_id             (refinement_id)
#  index_prompt_refinement_iterations_on_refinement_id_and_number  (refinement_id,number) UNIQUE
#  index_prompt_refinement_iterations_on_student_trial_id          (student_trial_id) UNIQUE
#
# Foreign Keys
#
#  prompt_revision_id  (prompt_revision_id => prompt_revisions.id)
#  refinement_id       (refinement_id => prompt_refinements.id)
#  student_trial_id    (student_trial_id => trials.id)
#
class PromptRefinementIteration < ApplicationRecord
  STATUSES = {
    pending: "pending",
    running_trial: "running_trial",
    evaluating: "evaluating",
    completed: "completed",
    failed: "failed"
  }.freeze

  VERDICTS = %w[match partial miss].freeze

  belongs_to :refinement, class_name: "PromptRefinement", inverse_of: :iterations
  # A revision of the refinement's working prompt.
  belongs_to :prompt_revision, inverse_of: :prompt_refinement_iterations
  belongs_to :student_trial, class_name: "Trial", optional: true, inverse_of: :refinement_iteration

  enum :status, STATUSES, validate: true

  validates :number, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :refinement_id }
  validates :agreement, numericality: { in: 0..1 }, allow_nil: true
  validate :prompt_revision_belongs_to_working_prompt
  validate :student_trial_matches_iteration
  validate :case_evaluations_are_well_formed

  before_update :prevent_changes_once_completed

  private

  def prompt_revision_belongs_to_working_prompt
    return unless refinement && prompt_revision
    return if prompt_revision.prompt_id == refinement.prompt_id

    errors.add(:prompt_revision, "must be a revision of the refinement's working prompt")
  end

  def student_trial_matches_iteration
    return unless refinement && student_trial

    unless student_trial.backend_id == refinement.student_backend_id && student_trial.model == refinement.student_model &&
        student_trial.prompt_revision_id == prompt_revision_id &&
        student_trial.test_suite_revision_id == refinement.test_suite_revision_id
      errors.add(:student_trial, "must run the student model on this iteration's prompt revision and the refinement's test suite revision")
    end
  end

  # Verdicts are keyed by test suite revision case id: { "12" => { "verdict" => "match", "notes" => "..." } }.
  def case_evaluations_are_well_formed
    well_formed = case_evaluations.is_a?(Hash) && case_evaluations.all? do |case_id, evaluation|
      case_id.to_s.match?(/\A\d+\z/) && evaluation.is_a?(Hash) &&
        VERDICTS.include?(evaluation["verdict"]) && evaluation.fetch("notes", "").is_a?(String)
    end
    errors.add(:case_evaluations, "must map test case ids to a verdict of #{VERDICTS.to_sentence(last_word_connector: ", or ")} and optional notes") unless well_formed
  end

  def prevent_changes_once_completed
    return unless status_in_database == STATUSES[:completed]

    errors.add(:base, "Completed refinement iterations are immutable")
    throw :abort
  end
end
