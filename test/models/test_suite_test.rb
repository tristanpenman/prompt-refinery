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
end
