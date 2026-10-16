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
end
