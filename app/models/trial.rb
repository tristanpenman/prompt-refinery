# == Schema Information
#
# Table name: trials
# Database name: primary
#
#  id                     :integer          not null, primary key
#  completed_at           :datetime
#  model                  :string           not null
#  started_at             :datetime
#  status                 :string           default("pending"), not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  collection_id          :integer          not null
#  collection_revision_id :integer          not null
#
# Indexes
#
#  index_trials_on_collection_id           (collection_id)
#  index_trials_on_collection_revision_id  (collection_revision_id)
#
# Foreign Keys
#
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
  has_many :responses, dependent: :destroy, inverse_of: :trial

  enum :status, STATUSES, validate: true

  validates :model, presence: true
  validate :revision_belongs_to_collection
  validate :collection_is_active, on: :create
  validate :collection_has_prompts, on: :create

  def self.create_for!(collection:, model:, **attributes)
    transaction do
      revision = CollectionRevision.capture!(collection)
      trial = create!(attributes.merge(collection: collection, collection_revision: revision, model: model))
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
end
