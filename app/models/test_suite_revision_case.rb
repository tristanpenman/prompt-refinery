# == Schema Information
#
# Table name: test_suite_revision_cases
# Database name: primary
#
#  id                     :integer          not null, primary key
#  position               :integer          not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  test_case_revision_id  :integer          not null
#  test_suite_revision_id :integer          not null
#
# Indexes
#
#  index_revision_cases_on_revision_and_case                  (test_suite_revision_id,test_case_revision_id) UNIQUE
#  index_revision_cases_on_revision_and_position              (test_suite_revision_id,position) UNIQUE
#  index_test_suite_revision_cases_on_test_case_revision_id   (test_case_revision_id)
#  index_test_suite_revision_cases_on_test_suite_revision_id  (test_suite_revision_id)
#
# Foreign Keys
#
#  test_case_revision_id   (test_case_revision_id => test_case_revisions.id)
#  test_suite_revision_id  (test_suite_revision_id => test_suite_revisions.id)
#
class TestSuiteRevisionCase < ApplicationRecord
  belongs_to :test_suite_revision, inverse_of: :test_suite_revision_cases
  belongs_to :test_case_revision, inverse_of: :test_suite_revision_cases
  has_many :responses, dependent: :restrict_with_error, inverse_of: :test_suite_revision_case

  validates :test_case_revision_id, uniqueness: { scope: :test_suite_revision_id }
  validates :position,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 },
    uniqueness: { scope: :test_suite_revision_id }

  before_update :prevent_changes

  private

  def prevent_changes
    errors.add(:base, "Test suite revision cases are immutable")
    throw :abort
  end
end
