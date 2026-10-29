# == Schema Information
#
# Table name: trials
# Database name: primary
#
#  id                     :integer          not null, primary key
#  backend_adapter        :string           default("ollama"), not null
#  backend_base_url       :string           not null
#  backend_name           :string           not null
#  completed_at           :datetime
#  model                  :string           not null
#  started_at             :datetime
#  status                 :string           default("pending"), not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  backend_id             :integer          not null
#  prompt_revision_id     :integer          not null
#  test_suite_revision_id :integer          not null
#
# Indexes
#
#  index_trials_on_backend_id              (backend_id)
#  index_trials_on_prompt_revision_id      (prompt_revision_id)
#  index_trials_on_test_suite_revision_id  (test_suite_revision_id)
#
# Foreign Keys
#
#  backend_id              (backend_id => backends.id)
#  prompt_revision_id      (prompt_revision_id => prompt_revisions.id)
#  test_suite_revision_id  (test_suite_revision_id => test_suite_revisions.id)
#
class Trial < ApplicationRecord
  STATUSES = {
    pending: "pending",
    running: "running",
    completed: "completed",
    failed: "failed"
  }.freeze

  belongs_to :prompt_revision, inverse_of: :trials
  belongs_to :test_suite_revision, inverse_of: :trials
  belongs_to :backend, inverse_of: :trials
  has_many :responses, dependent: :destroy, inverse_of: :trial
  has_one :reference_refinement,
    class_name: "PromptRefinement",
    foreign_key: :reference_trial_id,
    dependent: :restrict_with_error,
    inverse_of: :reference_trial
  has_one :refinement_iteration,
    class_name: "PromptRefinementIteration",
    foreign_key: :student_trial_id,
    dependent: :restrict_with_error,
    inverse_of: :student_trial

  enum :status, STATUSES, validate: true

  validates :model, presence: true
  validates :backend_name, :backend_base_url, presence: true
  validates :backend_adapter, inclusion: { in: Backend::ADAPTERS }
  validate :prompt_is_active, on: :create
  validate :test_suite_is_active, on: :create
  validate :test_suite_is_confirmed, on: :create
  validate :test_suite_has_test_cases, on: :create
  validate :test_suite_provides_prompt_variables, on: :create
  validate :backend_is_enabled, on: :create
  validate :execution_input_is_immutable, on: :update

  before_validation :snapshot_backend, on: :create

  def self.create_for!(prompt:, test_suite:, backend:, model:, **attributes)
    transaction do
      create_from_revisions!(
        prompt_revision: PromptRevision.capture!(prompt),
        test_suite_revision: TestSuiteRevision.capture!(test_suite),
        backend: backend,
        model: model,
        **attributes
      )
    end
  end

  # Creates a trial of revisions that were already captured, with a pending
  # response for each test case.
  def self.create_from_revisions!(prompt_revision:, test_suite_revision:, backend:, model:, backend_snapshot: nil, **attributes)
    transaction do
      trial = new(
        attributes.merge(
          prompt_revision: prompt_revision,
          test_suite_revision: test_suite_revision,
          backend: backend,
          model: model
        )
      )
      trial.backend_snapshot = backend_snapshot
      trial.save!
      template = PromptTemplate.new(prompt_revision.template)
      test_suite_revision.test_suite_revision_cases.includes(:test_case_revision).each do |member|
        trial.responses.create!(
          test_suite_revision_case: member,
          rendered_prompt: template.render(member.test_case_revision.values)
        )
      end
      trial
    end
  end

  attr_writer :backend_snapshot

  def inference_configuration
    { adapter: backend_adapter, base_url: backend_base_url }.freeze
  end

  def backend_snapshot
    { name: backend_name, **inference_configuration }.freeze
  end

  private

  def snapshot_backend
    return unless backend

    snapshot = @backend_snapshot || { name: backend.name, **backend.inference_configuration }
    self.backend_name = snapshot.fetch(:name)
    self.backend_base_url = snapshot.fetch(:base_url)
    self.backend_adapter = snapshot.fetch(:adapter)
  end

  def execution_input_is_immutable
    changed_fields = changes_to_save.keys
    if (changed_fields & %w[backend_id backend_name backend_base_url backend_adapter]).any?
      errors.add(:backend, "cannot be changed after the trial is created")
    end
    if (changed_fields & %w[prompt_revision_id test_suite_revision_id]).any?
      errors.add(:base, "Prompt and test suite revisions cannot be changed after the trial is created")
    end
  end

  def prompt_is_active
    errors.add(:prompt, "has been archived") if prompt_revision&.prompt&.archived_at?
  end

  def test_suite_is_active
    errors.add(:test_suite, "has been archived") if test_suite_revision&.test_suite&.archived_at?
  end

  def test_suite_is_confirmed
    errors.add(:test_suite, "has not finished importing") if test_suite_revision&.test_suite&.provisional?
  end

  def test_suite_has_test_cases
    return unless test_suite_revision
    return if test_suite_revision.test_suite_revision_cases.any?

    errors.add(:test_suite, "must contain at least one test case")
  end

  def test_suite_provides_prompt_variables
    return unless prompt_revision && test_suite_revision

    missing = PromptTemplate.new(prompt_revision.template).variables - test_suite_revision.variables
    return if missing.empty?

    errors.add(:test_suite, "does not provide #{"variable".pluralize(missing.size)} used by the prompt: #{missing.to_sentence}")
  end

  def backend_is_enabled
    errors.add(:backend, "must be enabled") if backend && !backend.enabled?
  end
end
