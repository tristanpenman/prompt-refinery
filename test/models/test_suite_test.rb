require "test_helper"

class TestSuiteTest < ActiveSupport::TestCase
  test "requires a name" do
    test_suite = TestSuite.new(name: "")

    assert_not test_suite.valid?
    assert_includes test_suite.errors[:name], "can't be blank"
  end

  test "defaults to no variables" do
    assert_equal [], TestSuite.create!(name: "Topics").variables
  end

  test "requires well-formed variable names" do
    test_suite = TestSuite.new(name: "Topics", variables: [ "topic", "two words" ])

    assert_not test_suite.valid?
    assert_includes test_suite.errors[:variables], "must be names made of letters, digits, and underscores"
  end

  test "requires unique variable names" do
    test_suite = TestSuite.new(name: "Topics", variables: [ "topic", "topic" ])

    assert_not test_suite.valid?
    assert_includes test_suite.errors[:variables], "must be unique"
  end

  test "an archived test suite can only be unarchived" do
    test_suite = TestSuite.create!(name: "Topics", variables: [ "topic" ])
    test_suite.archive!

    assert_includes TestSuite.archived, test_suite
    assert_not test_suite.update(name: "Changed")
    assert_includes test_suite.errors[:base], "Archived test suites are read-only"

    test_suite.unarchive!
    assert_includes TestSuite.active, test_suite
  end

  test "returns active test cases in position order" do
    test_suite = TestSuite.create!(name: "Topics", variables: [ "topic" ])
    second = test_suite.test_cases.create!(values: { "topic" => "Rust" }, position: 2)
    first = test_suite.test_cases.create!(values: { "topic" => "Ruby" }, position: 1)
    deleted = test_suite.test_cases.create!(values: { "topic" => "Perl" }, position: 0)

    deleted.soft_delete!

    assert_equal [ first, second ], test_suite.test_cases.reload.to_a
    assert_equal [ deleted ], test_suite.deleted_test_cases.reload.to_a
  end

  test "destroys its test cases" do
    test_suite = TestSuite.create!(name: "Topics", variables: [ "topic" ])
    test_case = test_suite.test_cases.create!(values: { "topic" => "Ruby" })

    test_suite.destroy!

    assert_not TestCase.exists?(test_case.id)
  end

  test "parses a comma-separated variable list" do
    test_suite = TestSuite.new(variable_list: " topic, audience ,, ")

    assert_equal [ "topic", "audience" ], test_suite.variables
    assert_equal "topic, audience", test_suite.variable_list
  end

  test "keeps test cases complete when variables change" do
    test_suite = TestSuite.create!(name: "Topics", variables: [ "topic", "tone" ])
    test_case = test_suite.test_cases.create!(values: { "topic" => "Ruby", "tone" => "formal" })

    test_suite.update!(variables: [ "topic", "audience" ])

    assert_equal({ "topic" => "Ruby", "audience" => "" }, test_case.reload.values)
    assert_predicate test_case, :valid?
  end

  test "requires variables while it has test cases" do
    test_suite = TestSuite.create!(name: "Topics", variables: [ "topic" ])
    test_suite.test_cases.create!(values: { "topic" => "Ruby" })

    assert_not test_suite.update(variables: [])
    assert_includes test_suite.errors[:variables], "can't be empty while the suite has test cases"
  end

  test "imports a provisional test suite from a CSV file" do
    contents = "topic,Target Audience\nRuby,beginners\nRust,experts\n"

    test_suite = TestSuite.import_csv!(file: csv_upload(contents, filename: "topics.csv"), header_row: true)

    assert test_suite.provisional?
    assert_equal "topics", test_suite.name
    assert_equal [ "topic", "Target_Audience" ], test_suite.variables
    assert_equal [
      [ { "topic" => "Ruby", "Target_Audience" => "beginners" }, 0 ],
      [ { "topic" => "Rust", "Target_Audience" => "experts" }, 1 ]
    ], test_suite.test_cases.reload.map { |test_case| [ test_case.values, test_case.position ] }
    assert_equal "topics.csv", test_suite.source_csv.filename.to_s
    assert_equal contents, test_suite.source_csv.download
  end

  test "stores the CSV file even if the test suite is reloaded before the transaction commits" do
    test_suite = TestSuite.transaction do
      TestSuite.import_csv!(file: csv_upload("topic\nRuby\n"), header_row: true).tap(&:reload)
    end

    assert_equal "topic\nRuby\n", test_suite.source_csv.download
  end

  test "imports a CSV file without a header row" do
    test_suite = TestSuite.import_csv!(file: csv_upload("Ruby,beginners\n"), header_row: false)

    assert_equal [ "column_1", "column_2" ], test_suite.variables
    assert_equal [ { "column_1" => "Ruby", "column_2" => "beginners" } ], test_suite.test_cases.map(&:values)
  end

  test "creates nothing when a CSV file can't be imported" do
    assert_no_difference [ "TestSuite.count", "TestCase.count", "ActiveStorage::Blob.count" ] do
      assert_raises(TestSuiteCsv::Error) do
        TestSuite.import_csv!(file: csv_upload("topic\nRuby,extra\n"), header_row: true)
      end
    end
  end

  test "a provisional test suite requires a source CSV" do
    test_suite = TestSuite.new(name: "Topics", provisional: true)

    assert_not test_suite.valid?
    assert_includes test_suite.errors[:source_csv], "must be attached to a provisional test suite"
  end

  test "confirming an import renames variables without losing values" do
    test_suite = TestSuite.import_csv!(file: csv_upload("a,b\nRuby,beginners\n"), header_row: true)

    test_suite.confirm_import!(name: "Topics", variable_names: { "a" => "topic", "b" => " audience " })

    test_suite.reload
    assert_not test_suite.provisional?
    assert_equal "Topics", test_suite.name
    assert_equal [ "topic", "audience" ], test_suite.variables
    assert_equal [ { "topic" => "Ruby", "audience" => "beginners" } ], test_suite.test_cases.map(&:values)
    assert test_suite.source_csv.attached?
  end

  test "confirming an import can swap variable names" do
    test_suite = TestSuite.import_csv!(file: csv_upload("a,b\nRuby,beginners\n"), header_row: true)

    test_suite.confirm_import!(name: "Topics", variable_names: { "a" => "b", "b" => "a" })

    assert_equal [ { "b" => "Ruby", "a" => "beginners" } ], test_suite.test_cases.reload.map(&:values)
  end

  test "confirming an import with invalid variable names changes nothing" do
    test_suite = TestSuite.import_csv!(file: csv_upload("a,b\nRuby,beginners\n"), header_row: true)

    assert_raises(ActiveRecord::RecordInvalid) do
      test_suite.confirm_import!(name: "Topics", variable_names: { "a" => "topic", "b" => "topic" })
    end

    test_suite.reload
    assert test_suite.provisional?
    assert_equal [ "a", "b" ], test_suite.variables
    assert_equal [ { "a" => "Ruby", "b" => "beginners" } ], test_suite.test_cases.map(&:values)
  end

  test "only provisional test suites can be confirmed" do
    test_suite = TestSuite.create!(name: "Topics", variables: [ "topic" ])

    error = assert_raises(ActiveRecord::RecordInvalid) { test_suite.confirm_import!(name: "Topics") }
    assert_includes error.record.errors[:base], "Only provisional test suites can be confirmed"
  end

  test "a confirmed test suite can't become provisional again" do
    test_suite = TestSuite.import_csv!(file: csv_upload("topic\nRuby\n"), header_row: true)
    test_suite.confirm_import!(name: "Topics")

    assert_not test_suite.update(provisional: true)
    assert_includes test_suite.errors[:provisional], "can't be restored once the import is confirmed"
  end

  private

  def csv_upload(contents, filename: "import.csv")
    Rack::Test::UploadedFile.new(StringIO.new(contents), "text/csv", original_filename: filename)
  end
end
