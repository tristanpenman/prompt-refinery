# == Schema Information
#
# Table name: prompts
# Database name: primary
#
#  id          :integer          not null, primary key
#  archived_at :datetime
#  name        :string           not null
#  template    :text             not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
# Indexes
#
#  index_prompts_on_archived_at  (archived_at)
#
class Prompt < ApplicationRecord
  scope :active, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }

  has_many :prompt_revisions, dependent: :destroy, inverse_of: :prompt

  validates :name, presence: true
  validates :template, presence: true
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

    errors.add(:base, "Archived prompts are read-only")
  end
end
