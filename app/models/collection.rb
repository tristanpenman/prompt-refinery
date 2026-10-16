# == Schema Information
#
# Table name: collections
# Database name: primary
#
#  id          :integer          not null, primary key
#  archived_at :datetime
#  name        :string           not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
# Indexes
#
#  index_collections_on_archived_at  (archived_at)
#
class Collection < ApplicationRecord
  scope :active, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }
  scope :with_prompts, -> { joins(:prompts).distinct }

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
  validate :read_only_while_archived, on: :update

  def archive!
    update!(archived_at: Time.current)
  end

  def unarchive!
    reload.update!(archived_at: nil)
  end

  private

  def read_only_while_archived
    return unless archived_at_in_database.present?
    return if changes_to_save.keys == [ "archived_at" ] && archived_at.nil?

    errors.add(:base, "Archived collections are read-only")
  end
end
