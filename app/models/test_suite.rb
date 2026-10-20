# == Schema Information
#
# Table name: test_suites
# Database name: primary
#
#  id          :integer          not null, primary key
#  archived_at :datetime
#  name        :string           not null
#  provisional :boolean          default(FALSE), not null
#  variables   :json             not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
# Indexes
#
#  index_test_suites_on_archived_at  (archived_at)
#  index_test_suites_on_provisional  (provisional)
#
class TestSuite < ApplicationRecord
  VARIABLE_NAME = /\A#{PromptTemplate::VARIABLE_NAME}\z/

  scope :active, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }

  has_many :test_suite_revisions, dependent: :destroy, inverse_of: :test_suite
  has_many :test_cases,
    -> { where(deleted_at: nil).order(:position, :id) },
    dependent: :destroy,
    inverse_of: :test_suite
  has_many :deleted_test_cases,
    -> { where.not(deleted_at: nil).order(:position, :id) },
    class_name: "TestCase",
    dependent: :destroy
  has_one_attached :source_csv

  validates :name, presence: true
  validate :variables_are_well_formed
  validate :variables_present_while_cases_exist, on: :update
  validate :read_only_while_archived, on: :update
  validate :source_csv_attached_while_provisional
  validate :provisional_only_until_confirmed, on: :update

  after_update :reconcile_test_case_values, if: :saved_change_to_variables?

  # Creates a provisional test suite from an uploaded CSV file, with a test
  # case for each row. Raises TestSuiteCsv::Error if the file can't be imported.
  def self.import_csv!(file:, header_row:)
    parsed = TestSuiteCsv.parse(file, header_row: header_row)
    file.rewind

    new(
      name: File.basename(file.original_filename.to_s, ".*").presence || "Imported test suite",
      variables: parsed.variables,
      provisional: true,
      source_csv: file
    ).tap do |test_suite|
      parsed.rows.each_with_index do |values, position|
        test_suite.test_cases.build(values: values, position: position)
      end
      test_suite.save!
    end
  end

  # Finishes an import, applying the chosen name and any variable renames
  # given as a hash of current names to new names.
  def confirm_import!(name:, variable_names: {})
    unless provisional?
      errors.add(:base, "Only provisional test suites can be confirmed")
      raise ActiveRecord::RecordInvalid, self
    end

    mapping = variables.index_with { |variable| variable_names.fetch(variable, variable).to_s.strip }

    transaction do
      # Rename values before the variables, so reconcile_test_case_values keeps them.
      TestCase.where(test_suite: self).find_each do |test_case|
        test_case.update_columns(values: test_case.values.transform_keys(mapping))
      end
      update!(name: name, variables: variables.map(&mapping), provisional: false)
    end
  end

  def archive!
    update!(archived_at: Time.current)
  end

  def unarchive!
    reload.update!(archived_at: nil)
  end

  def variable_list
    variables.join(", ")
  end

  def variable_list=(text)
    self.variables = text.to_s.split(",").map(&:strip).reject(&:empty?)
  end

  private

  def variables_are_well_formed
    unless variables.is_a?(Array) && variables.all? { |name| name.is_a?(String) && name.match?(VARIABLE_NAME) }
      errors.add(:variables, "must be names made of letters, digits, and underscores")
      return
    end

    errors.add(:variables, "must be unique") if variables.uniq.size != variables.size
  end

  def variables_present_while_cases_exist
    errors.add(:variables, "can't be empty while the suite has test cases") if variables.empty? && test_cases.exists?
  end

  # Drops values for removed variables and adds blank values for new ones,
  # so existing test cases stay complete when the suite's variables change.
  def reconcile_test_case_values
    TestCase.where(test_suite: self).find_each do |test_case|
      values = variables.index_with { |name| test_case.values.fetch(name, "") }
      test_case.update_columns(values: values) unless values == test_case.values
    end
  end

  def source_csv_attached_while_provisional
    errors.add(:source_csv, "must be attached to a provisional test suite") if provisional? && !source_csv.attached?
  end

  def provisional_only_until_confirmed
    errors.add(:provisional, "can't be restored once the import is confirmed") if provisional_changed?(from: false, to: true)
  end

  def read_only_while_archived
    return unless archived_at_in_database.present?
    return if changes_to_save.keys == [ "archived_at" ] && archived_at.nil?

    errors.add(:base, "Archived test suites are read-only")
  end
end
