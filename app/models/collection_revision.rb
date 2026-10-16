require "digest"
# == Schema Information
#
# Table name: collection_revisions
# Database name: primary
#
#  id             :integer          not null, primary key
#  content_digest :string           not null
#  name           :string           not null
#  version        :integer          not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  collection_id  :integer          not null
#
# Indexes
#
#  index_collection_revisions_on_collection_id                     (collection_id)
#  index_collection_revisions_on_collection_id_and_content_digest  (collection_id,content_digest) UNIQUE
#  index_collection_revisions_on_collection_id_and_version         (collection_id,version) UNIQUE
#
# Foreign Keys
#
#  collection_id  (collection_id => collections.id)
#
class CollectionRevision < ApplicationRecord
  belongs_to :collection, inverse_of: :collection_revisions
  has_many :collection_revision_prompts,
    -> { order(:position, :id) },
    dependent: :destroy,
    inverse_of: :collection_revision
  has_many :prompt_revisions, through: :collection_revision_prompts
  has_many :trials, dependent: :restrict_with_error, inverse_of: :collection_revision

  validates :version, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :collection_id }
  validates :name, :content_digest, presence: true
  validates :content_digest, uniqueness: { scope: :collection_id }

  before_update :prevent_changes

  def self.capture!(collection)
    collection.with_lock do
      prompts = collection.prompts.to_a
      digest = content_digest_for(collection, prompts)
      existing = find_by(collection: collection, content_digest: digest)
      return existing if existing

      create!(
        collection: collection,
        version: where(collection: collection).maximum(:version).to_i + 1,
        name: collection.name,
        content_digest: digest
      ).tap do |revision|
        prompts.each_with_index do |prompt, position|
          revision.collection_revision_prompts.create!(
            prompt_revision: PromptRevision.capture!(prompt),
            position: position
          )
        end
      end
    end
  end

  def self.content_digest_for(collection, prompts)
    Digest::SHA256.hexdigest(
      [ collection.name, prompts.map { |prompt| [ prompt.id, prompt.name, prompt.template, prompt.position ] } ].to_json
    )
  end

  private

  def prevent_changes
    errors.add(:base, "Collection revisions are immutable")
    throw :abort
  end
end
