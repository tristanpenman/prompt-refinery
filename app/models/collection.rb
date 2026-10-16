class Collection < ApplicationRecord
  scope :active, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }

  has_many :trials, dependent: :restrict_with_error, inverse_of: :collection
  has_many :collection_revisions, dependent: :destroy, inverse_of: :collection
  has_many :prompts,
    -> { where(deleted_at: nil).order(:position, :id) },
    dependent: :destroy,
    inverse_of: :collection
  has_many :deleted_prompts,
    -> { where.not(deleted_at: nil).order(:position, :id) },
    class_name: "Prompt",
    dependent: :destroy

  validates :name, presence: true

  def archive!
    update!(archived_at: Time.current)
  end

  def unarchive!
    update!(archived_at: nil)
  end
end
