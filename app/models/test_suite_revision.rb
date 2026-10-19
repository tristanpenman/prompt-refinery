require "digest"

# == Schema Information
#
# Table name: test_suite_revisions
# Database name: primary
#
#  id             :integer          not null, primary key
#  content_digest :string           not null
#  name           :string           not null
#  variables      :json             not null
#  version        :integer          not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  test_suite_id  :integer          not null
#
# Indexes
#
#  index_test_suite_revisions_on_test_suite_id                     (test_suite_id)
#  index_test_suite_revisions_on_test_suite_id_and_content_digest  (test_suite_id,content_digest) UNIQUE
#  index_test_suite_revisions_on_test_suite_id_and_version         (test_suite_id,version) UNIQUE
#
# Foreign Keys
#
#  test_suite_id  (test_suite_id => test_suites.id)
#
class TestSuiteRevision < ApplicationRecord
  belongs_to :test_suite, inverse_of: :test_suite_revisions
  has_many :test_suite_revision_cases,
    -> { order(:position, :id) },
    dependent: :destroy,
    inverse_of: :test_suite_revision
  has_many :test_case_revisions, through: :test_suite_revision_cases
  has_many :trials, dependent: :restrict_with_error, inverse_of: :test_suite_revision

  validates :version, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :test_suite_id }
  validates :name, :content_digest, presence: true
  validates :content_digest, uniqueness: { scope: :test_suite_id }

  before_update :prevent_changes

  def self.capture!(test_suite)
    test_suite.with_lock do
      test_cases = test_suite.test_cases.to_a
      digest = content_digest_for(test_suite, test_cases)
      existing = find_by(test_suite: test_suite, content_digest: digest)
      return existing if existing

      create!(
        test_suite: test_suite,
        version: where(test_suite: test_suite).maximum(:version).to_i + 1,
        name: test_suite.name,
        variables: test_suite.variables,
        content_digest: digest
      ).tap do |revision|
        test_cases.each_with_index do |test_case, position|
          revision.test_suite_revision_cases.create!(
            test_case_revision: TestCaseRevision.capture!(test_case),
            position: position
          )
        end
      end
    end
  end

  def self.content_digest_for(test_suite, test_cases)
    Digest::SHA256.hexdigest(
      [
        test_suite.name,
        test_suite.variables,
        test_cases.map { |test_case| [ test_case.id, test_case.values.sort, test_case.position ] }
      ].to_json
    )
  end

  private

  def prevent_changes
    errors.add(:base, "Test suite revisions are immutable")
    throw :abort
  end
end
