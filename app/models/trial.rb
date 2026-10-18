# == Schema Information
#
# Table name: trials
# Database name: primary
#
#  id                     :integer          not null, primary key
#  backend_base_url       :string           not null
#  backend_name           :string           not null
#  completed_at           :datetime
#  model                  :string           not null
#  started_at             :datetime
#  status                 :string           default("pending"), not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  backend_id             :integer          not null
#  collection_id          :integer          not null
#  collection_revision_id :integer          not null
#
# Indexes
#
#  index_trials_on_backend_id              (backend_id)
#  index_trials_on_collection_id           (collection_id)
#  index_trials_on_collection_revision_id  (collection_revision_id)
#
# Foreign Keys
#
#  backend_id              (backend_id => backends.id)
#  collection_id           (collection_id => collections.id)
#  collection_revision_id  (collection_revision_id => collection_revisions.id)
#
class Trial < ApplicationRecord
  STATUSES = {
    pending: "pending",
    running: "running",
    completed: "completed",
    failed: "failed"
  }.freeze

  belongs_to :collection
  belongs_to :collection_revision, inverse_of: :trials
  belongs_to :backend, inverse_of: :trials
  has_many :responses, dependent: :destroy, inverse_of: :trial

  enum :status, STATUSES, validate: true

  validates :model, presence: true
  validates :backend_name, :backend_base_url, presence: true
  validate :revision_belongs_to_collection
  validate :collection_is_active, on: :create
  validate :collection_has_prompts, on: :create
  validate :backend_is_enabled, on: :create
  validate :backend_execution_input_is_immutable, on: :update

  before_validation :snapshot_backend, on: :create

  def self.create_for!(collection:, backend:, model:, **attributes)
    transaction do
      revision = CollectionRevision.capture!(collection)
      trial = create!(
        attributes.merge(
          collection: collection,
          collection_revision: revision,
          backend: backend,
          model: model
        )
      )
      revision.collection_revision_prompts.each do |member|
        trial.responses.create!(
          prompt: member.prompt_revision.prompt,
          collection_revision_prompt: member,
          rendered_prompt: member.prompt_revision.template
        )
      end
      trial
    end
  end

  private

  def snapshot_backend
    return unless backend

    self.backend_name = backend.name
    self.backend_base_url = backend.base_url
  end

  def backend_execution_input_is_immutable
    immutable_fields = %w[backend_id backend_name backend_base_url]
    return if (changes_to_save.keys & immutable_fields).empty?

    errors.add(:backend, "cannot be changed after the trial is created")
  end

  def revision_belongs_to_collection
    return unless collection && collection_revision
    return if collection_revision.collection_id == collection_id

    errors.add(:collection_revision, "must belong to the trial's collection")
  end

  def collection_is_active
    errors.add(:collection, "has been archived") if collection&.archived_at?
  end

  def collection_has_prompts
    errors.add(:collection, "must contain at least one prompt") if collection && collection.prompts.empty?
  end

  def backend_is_enabled
    errors.add(:backend, "must be enabled") if backend && !backend.enabled?
  end
end
