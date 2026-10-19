require "test_helper"

class TestSuiteRevisionTest < ActiveSupport::TestCase
  setup do
    @test_suite = TestSuite.create!(name: "Topics", variables: [ "topic" ])
    @test_case = @test_suite.test_cases.create!(values: { "topic" => "Ruby" }, position: 0)
  end

  test "reuses a revision when the test suite has not changed" do
    first = TestSuiteRevision.capture!(@test_suite)
    second = TestSuiteRevision.capture!(@test_suite)

    assert_equal first, second
    assert_equal 1, @test_suite.test_suite_revisions.count
  end

  test "captures new test suite and test case revisions after an edit" do
    first = TestSuiteRevision.capture!(@test_suite)
    @test_case.update!(values: { "topic" => "Rust" })

    second = TestSuiteRevision.capture!(@test_suite)

    assert_equal 1, first.version
    assert_equal 2, second.version
    assert_equal({ "topic" => "Ruby" }, first.test_case_revisions.first.values)
    assert_equal({ "topic" => "Rust" }, second.test_case_revisions.first.values)
    assert_equal [ 1, 2 ], @test_case.test_case_revisions.order(:version).pluck(:version)
  end

  test "reuses unchanged test case revisions in a new suite revision" do
    first = TestSuiteRevision.capture!(@test_suite)
    @test_suite.update!(name: "Subjects")

    second = TestSuiteRevision.capture!(@test_suite)

    assert_equal [ "Topics", "Subjects" ], [ first.name, second.name ]
    assert_equal first.test_case_revisions.to_a, second.test_case_revisions.to_a
  end

  test "records variables and test case membership in position order" do
    second = @test_suite.test_cases.create!(values: { "topic" => "Rust" }, position: 1)
    deleted = @test_suite.test_cases.create!(values: { "topic" => "Perl" }, position: 2)
    deleted.soft_delete!

    revision = TestSuiteRevision.capture!(@test_suite)

    assert_equal [ "topic" ], revision.variables
    assert_equal [ @test_case, second ], revision.test_case_revisions.map(&:test_case)
    assert_equal [ 0, 1 ], revision.test_suite_revision_cases.map(&:position)
  end

  test "ignores the order of test case values" do
    test_suite = TestSuite.create!(name: "Pairs", variables: [ "topic", "audience" ])
    test_case = test_suite.test_cases.create!(values: { "topic" => "Ruby", "audience" => "experts" })
    first = TestCaseRevision.capture!(test_case)
    test_case.update!(values: { "audience" => "experts", "topic" => "Ruby" })

    assert_equal first, TestCaseRevision.capture!(test_case)
  end

  test "cannot be changed after capture" do
    revision = TestSuiteRevision.capture!(@test_suite)

    assert_not revision.update(name: "Changed")
    assert_includes revision.errors[:base], "Test suite revisions are immutable"
    assert_not revision.test_suite_revision_cases.first.update(position: 5)
    assert_not revision.test_case_revisions.first.update(values: { "topic" => "Changed" })
  end

  test "is destroyed with its test suite" do
    TestSuiteRevision.capture!(@test_suite)

    assert_difference [ "TestSuiteRevision.count", "TestCaseRevision.count", "TestSuiteRevisionCase.count" ], -1 do
      @test_suite.reload.destroy!
    end
  end
end
