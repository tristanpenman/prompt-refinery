# == Schema Information
#
# Table name: collection_revision_prompts
# Database name: primary
#
#  id                     :integer          not null, primary key
#  position               :integer          not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  collection_revision_id :integer          not null
#  prompt_revision_id     :integer          not null
#
# Indexes
#
#  index_collection_revision_prompts_on_collection_revision_id  (collection_revision_id)
#  index_collection_revision_prompts_on_prompt_revision_id      (prompt_revision_id)
#  index_revision_prompts_on_revision_and_position              (collection_revision_id,position) UNIQUE
#  index_revision_prompts_on_revision_and_prompt                (collection_revision_id,prompt_revision_id) UNIQUE
#
# Foreign Keys
#
#  collection_revision_id  (collection_revision_id => collection_revisions.id)
#  prompt_revision_id      (prompt_revision_id => prompt_revisions.id)
#
class CollectionRevisionPrompt < ApplicationRecord
  belongs_to :collection_revision, inverse_of: :collection_revision_prompts
  belongs_to :prompt_revision, inverse_of: :collection_revision_prompts

  validates :prompt_revision_id, uniqueness: { scope: :collection_revision_id }
  validates :position,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 },
    uniqueness: { scope: :collection_revision_id }

  before_update :prevent_changes

  private

  def prevent_changes
    errors.add(:base, "Collection revision prompts are immutable")
    throw :abort
  end
end
