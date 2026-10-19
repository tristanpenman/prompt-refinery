# == Schema Information
#
# Table name: test_cases
# Database name: primary
#
#  id            :integer          not null, primary key
#  deleted_at    :datetime
#  position      :integer          default(0), not null
#  values        :json             not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  test_suite_id :integer          not null
#
# Indexes
#
#  index_test_cases_on_deleted_at                  (deleted_at)
#  index_test_cases_on_test_suite_id               (test_suite_id)
#  index_test_cases_on_test_suite_id_and_position  (test_suite_id,position)
#
# Foreign Keys
#
#  test_suite_id  (test_suite_id => test_suites.id)
#
class TestCase < ApplicationRecord
  belongs_to :test_suite, inverse_of: :test_cases

  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :values_match_suite_variables
  validate :test_suite_is_active

  def soft_delete!
    update!(deleted_at: Time.current)
  end

  private

  def values_match_suite_variables
    unless values.is_a?(Hash) && values.values.all?(String)
      errors.add(:values, "must map variable names to text")
      return
    end

    errors.add(:values, "must replace at least one variable") if values.empty?
    return unless test_suite

    missing = test_suite.variables - values.keys
    unknown = values.keys - test_suite.variables
    errors.add(:values, "are missing #{missing.to_sentence}") if missing.any?
    errors.add(:values, "include unknown variables #{unknown.to_sentence}") if unknown.any?
  end

  def test_suite_is_active
    errors.add(:test_suite, "has been archived") if test_suite&.archived_at?
  end
end
