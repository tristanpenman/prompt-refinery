class Prompt < ApplicationRecord
  belongs_to :collection, inverse_of: :prompts
  has_many :responses, dependent: :restrict_with_error, inverse_of: :prompt
  has_many :prompt_revisions, dependent: :destroy, inverse_of: :prompt

  validates :name, presence: true
  validates :template, presence: true
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :collection_is_active

  def soft_delete!
    update!(deleted_at: Time.current)
  end

  private

  def collection_is_active
    errors.add(:collection, "has been archived") if collection&.archived_at?
  end
end
