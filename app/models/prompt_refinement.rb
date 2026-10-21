# Not named Refinement, which is a core Ruby class.
# == Schema Information
#
# Table name: prompt_refinements
# Database name: primary
#
#  id                          :integer          not null, primary key
#  completed_at                :datetime
#  context_size                :integer          default(16384), not null
#  instructions                :text             not null
#  max_iterations              :integer          default(3), not null
#  name                        :string           not null
#  started_at                  :datetime
#  status                      :string           default("pending"), not null
#  stop_reason                 :string
#  stop_requested_at           :datetime
#  student_backend_base_url    :string           not null
#  student_backend_name        :string           not null
#  student_model               :string           not null
#  target_agreement            :decimal(4, 3)    default(1.0), not null
#  teacher_backend_base_url    :string           not null
#  teacher_backend_name        :string           not null
#  teacher_model               :string           not null
#  created_at                  :datetime         not null
#  updated_at                  :datetime         not null
#  prompt_id                   :integer          not null
#  reference_trial_id          :integer
#  starting_prompt_revision_id :integer          not null
#  student_backend_id          :integer          not null
#  teacher_backend_id          :integer          not null
#  test_suite_revision_id      :integer          not null
#
# Indexes
#
#  index_prompt_refinements_on_prompt_id                    (prompt_id) UNIQUE
#  index_prompt_refinements_on_reference_trial_id           (reference_trial_id) UNIQUE
#  index_prompt_refinements_on_starting_prompt_revision_id  (starting_prompt_revision_id)
#  index_prompt_refinements_on_student_backend_id           (student_backend_id)
#  index_prompt_refinements_on_teacher_backend_id           (teacher_backend_id)
#  index_prompt_refinements_on_test_suite_revision_id       (test_suite_revision_id)
#
# Foreign Keys
#
#  prompt_id                    (prompt_id => prompts.id)
#  reference_trial_id           (reference_trial_id => trials.id)
#  starting_prompt_revision_id  (starting_prompt_revision_id => prompt_revisions.id)
#  student_backend_id           (student_backend_id => backends.id)
#  teacher_backend_id           (teacher_backend_id => backends.id)
#  test_suite_revision_id       (test_suite_revision_id => test_suite_revisions.id)
#
class PromptRefinement < ApplicationRecord
  STATUSES = {
    pending: "pending",
    running: "running",
    completed: "completed",
    stopped: "stopped",
    failed: "failed"
  }.freeze

  STOP_REASONS = {
    max_iterations: "max_iterations",
    target_reached: "target_reached",
    converged: "converged",
    cancelled: "cancelled",
    failed: "failed"
  }.freeze

  MAX_ITERATIONS = 1..10
  INSTRUCTION_VARIABLES = %w[current_prompt variables cases history].freeze
  DEFAULT_INSTRUCTIONS_PATH = Rails.root.join("app/prompts/refinement_evaluator.md")

  # Inputs that define the exercise, fixed once it is created.
  EXECUTION_INPUTS = %w[
    prompt_id starting_prompt_revision_id test_suite_revision_id
    student_backend_id student_model student_backend_name student_backend_base_url
    teacher_backend_id teacher_model teacher_backend_name teacher_backend_base_url
    instructions
  ].freeze

  # The working prompt, which receives a revision for each iteration.
  belongs_to :prompt, inverse_of: :refinement
  belongs_to :starting_prompt_revision, class_name: "PromptRevision", inverse_of: :started_refinements
  belongs_to :test_suite_revision, inverse_of: :prompt_refinements
  belongs_to :student_backend, class_name: "Backend", inverse_of: :student_refinements
  belongs_to :teacher_backend, class_name: "Backend", inverse_of: :teacher_refinements
  belongs_to :reference_trial, class_name: "Trial", optional: true, inverse_of: :reference_refinement
  has_many :iterations,
    -> { order(:number) },
    class_name: "PromptRefinementIteration",
    foreign_key: :refinement_id,
    dependent: :destroy,
    inverse_of: :refinement

  enum :status, STATUSES, validate: true
  enum :stop_reason, STOP_REASONS, prefix: :stopped_by, validate: { allow_nil: true }

  validates :name, :student_model, :teacher_model, :instructions, presence: true
  validates :student_backend_name, :student_backend_base_url, :teacher_backend_name, :teacher_backend_base_url, presence: true
  validates :max_iterations, numericality: { only_integer: true, in: MAX_ITERATIONS }
  validates :target_agreement, numericality: { in: 0..1 }
  validates :context_size, numericality: { only_integer: true, greater_than: 0 }
  validate :instructions_use_known_variables
  validate :working_prompt_is_separate
  validate :prompt_is_active, on: :create
  validate :test_suite_is_usable, on: :create
  validate :test_suite_provides_prompt_variables, on: :create
  validate :backends_are_enabled, on: :create
  validate :reference_trial_matches_teacher
  validate :execution_input_is_immutable, on: :update

  before_validation :snapshot_backends, on: :create
  before_validation -> { self.instructions = self.class.default_instructions if instructions.nil? }, on: :create

  def self.default_instructions
    DEFAULT_INSTRUCTIONS_PATH.read
  end

  private

  def snapshot_backends
    if student_backend
      self.student_backend_name = student_backend.name
      self.student_backend_base_url = student_backend.base_url
    end
    if teacher_backend
      self.teacher_backend_name = teacher_backend.name
      self.teacher_backend_base_url = teacher_backend.base_url
    end
  end

  def instructions_use_known_variables
    unknown = PromptTemplate.new(instructions).variables - INSTRUCTION_VARIABLES
    return if unknown.empty?

    errors.add(:instructions, "use unknown #{"variable".pluralize(unknown.size)} #{unknown.to_sentence}; " \
      "available variables are #{INSTRUCTION_VARIABLES.to_sentence}")
  end

  # Refinements never write revisions to the prompt they started from.
  def working_prompt_is_separate
    return unless prompt_id && starting_prompt_revision

    errors.add(:prompt, "must be a separate working prompt, not the prompt being refined") if prompt_id == starting_prompt_revision.prompt_id
  end

  def prompt_is_active
    errors.add(:starting_prompt_revision, "belongs to an archived prompt") if starting_prompt_revision&.prompt&.archived_at?
  end

  def test_suite_is_usable
    test_suite = test_suite_revision&.test_suite
    return unless test_suite

    errors.add(:test_suite_revision, "belongs to an archived test suite") if test_suite.archived_at?
    errors.add(:test_suite_revision, "must contain at least one test case") if test_suite_revision.test_suite_revision_cases.none?
  end

  def test_suite_provides_prompt_variables
    return unless starting_prompt_revision && test_suite_revision

    missing = PromptTemplate.new(starting_prompt_revision.template).variables - test_suite_revision.variables
    return if missing.empty?

    errors.add(:test_suite_revision, "does not provide #{"variable".pluralize(missing.size)} used by the prompt: #{missing.to_sentence}")
  end

  def backends_are_enabled
    errors.add(:student_backend, "must be enabled") if student_backend && !student_backend.enabled?
    errors.add(:teacher_backend, "must be enabled") if teacher_backend && !teacher_backend.enabled?
  end

  def reference_trial_matches_teacher
    return unless reference_trial

    unless reference_trial.backend_id == teacher_backend_id && reference_trial.model == teacher_model &&
        reference_trial.prompt_revision_id == starting_prompt_revision_id &&
        reference_trial.test_suite_revision_id == test_suite_revision_id
      errors.add(:reference_trial, "must run the teacher model on the starting prompt revision and test suite revision")
    end
  end

  def execution_input_is_immutable
    changed = changes_to_save.keys & EXECUTION_INPUTS
    errors.add(:base, "#{changed.map(&:humanize).to_sentence} cannot be changed after the refinement is created") if changed.any?
    errors.add(:reference_trial, "cannot be replaced") if reference_trial_id_in_database && reference_trial_id_changed?
  end
end
