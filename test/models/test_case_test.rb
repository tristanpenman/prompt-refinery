require "test_helper"

class TestCaseTest < ActiveSupport::TestCase
  setup do
    @test_suite = TestSuite.create!(name: "Topics", variables: [ "topic", "audience" ])
  end

  test "stores a replacement for every suite variable" do
    test_case = @test_suite.test_cases.create!(values: { "topic" => "Ruby", "audience" => "beginners" })

    assert_equal({ "topic" => "Ruby", "audience" => "beginners" }, test_case.reload.values)
  end

  test "requires a test suite and at least one replacement" do
    test_case = TestCase.new

    assert_not test_case.valid?
    assert_includes test_case.errors[:test_suite], "must exist"
    assert_includes test_case.errors[:values], "must replace at least one variable"
  end

  test "requires a replacement for every suite variable" do
    test_case = @test_suite.test_cases.build(values: { "topic" => "Ruby" })

    assert_not test_case.valid?
    assert_includes test_case.errors[:values], "are missing audience"
  end

  test "rejects variables the suite does not define" do
    test_case = @test_suite.test_cases.build(values: { "topic" => "Ruby", "audience" => "experts", "tone" => "formal" })

    assert_not test_case.valid?
    assert_includes test_case.errors[:values], "include unknown variables tone"
  end

  test "requires replacements to be text" do
    test_case = @test_suite.test_cases.build(values: { "topic" => "Ruby", "audience" => 3 })

    assert_not test_case.valid?
    assert_includes test_case.errors[:values], "must map variable names to text"
  end

  test "requires a non-negative integer position" do
    test_case = @test_suite.test_cases.build(values: { "topic" => "Ruby", "audience" => "experts" }, position: -1)

    assert_not test_case.valid?
    assert_includes test_case.errors[:position], "must be greater than or equal to 0"
  end

  test "cannot be changed while its test suite is archived" do
    test_case = @test_suite.test_cases.create!(values: { "topic" => "Ruby", "audience" => "experts" })
    @test_suite.archive!

    assert_not test_case.update(position: 1)
    assert_includes test_case.errors[:test_suite], "has been archived"
    assert_raises(ActiveRecord::RecordInvalid) { test_case.soft_delete! }
  end
end
