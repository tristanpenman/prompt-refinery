class CollectionRevisionPrompt < ApplicationRecord
  belongs_to :collection_revision, inverse_of: :collection_revision_prompts
  belongs_to :prompt_revision, inverse_of: :collection_revision_prompts
  has_many :responses, dependent: :restrict_with_error, inverse_of: :collection_revision_prompt

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
