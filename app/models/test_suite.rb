# == Schema Information
#
# Table name: test_suites
# Database name: primary
#
#  id          :integer          not null, primary key
#  archived_at :datetime
#  name        :string           not null
#  variables   :json             not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
# Indexes
#
#  index_test_suites_on_archived_at  (archived_at)
#
class TestSuite < ApplicationRecord
  VARIABLE_NAME = /\A[A-Za-z_][A-Za-z0-9_]*\z/

  scope :active, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }

  has_many :test_cases,
    -> { where(deleted_at: nil).order(:position, :id) },
    dependent: :destroy,
    inverse_of: :test_suite
  has_many :deleted_test_cases,
    -> { where.not(deleted_at: nil).order(:position, :id) },
    class_name: "TestCase",
    dependent: :destroy

  validates :name, presence: true
  validate :variables_are_well_formed
  validate :read_only_while_archived, on: :update

  def archive!
    update!(archived_at: Time.current)
  end

  def unarchive!
    reload.update!(archived_at: nil)
  end

  private

  def variables_are_well_formed
    unless variables.is_a?(Array) && variables.all? { |name| name.is_a?(String) && name.match?(VARIABLE_NAME) }
      errors.add(:variables, "must be names made of letters, digits, and underscores")
      return
    end

    errors.add(:variables, "must be unique") if variables.uniq.size != variables.size
  end

  def read_only_while_archived
    return unless archived_at_in_database.present?
    return if changes_to_save.keys == [ "archived_at" ] && archived_at.nil?

    errors.add(:base, "Archived test suites are read-only")
  end
end
