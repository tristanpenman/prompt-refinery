require "digest"

# == Schema Information
#
# Table name: test_case_revisions
# Database name: primary
#
#  id             :integer          not null, primary key
#  content_digest :string           not null
#  values         :json             not null
#  version        :integer          not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  test_case_id   :integer          not null
#
# Indexes
#
#  index_test_case_revisions_on_test_case_id                     (test_case_id)
#  index_test_case_revisions_on_test_case_id_and_content_digest  (test_case_id,content_digest) UNIQUE
#  index_test_case_revisions_on_test_case_id_and_version         (test_case_id,version) UNIQUE
#
# Foreign Keys
#
#  test_case_id  (test_case_id => test_cases.id)
#
class TestCaseRevision < ApplicationRecord
  belongs_to :test_case, inverse_of: :test_case_revisions
  has_many :test_suite_revision_cases, dependent: :restrict_with_error, inverse_of: :test_case_revision

  validates :version, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :test_case_id }
  validates :content_digest, presence: true, uniqueness: { scope: :test_case_id }

  before_update :prevent_changes

  def self.capture!(test_case)
    test_case.with_lock do
      digest = Digest::SHA256.hexdigest(test_case.values.sort.to_json)
      find_by(test_case: test_case, content_digest: digest) || create!(
        test_case: test_case,
        version: where(test_case: test_case).maximum(:version).to_i + 1,
        values: test_case.values,
        content_digest: digest
      )
    end
  end

  private

  def prevent_changes
    errors.add(:base, "Test case revisions are immutable")
    throw :abort
  end
end
