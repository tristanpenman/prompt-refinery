require "test_helper"

class TestSuiteCsvTest < ActiveSupport::TestCase
  test "derives variables from the header row and test cases from the other rows" do
    result = TestSuiteCsv.parse("topic,audience\nRuby,beginners\nRust,experts\n", header_row: true)

    assert_equal [ "topic", "audience" ], result.variables
    assert_equal [ "topic", "audience" ], result.headers
    assert_equal [
      { "topic" => "Ruby", "audience" => "beginners" },
      { "topic" => "Rust", "audience" => "experts" }
    ], result.rows
  end

  test "names columns by position without a header row" do
    result = TestSuiteCsv.parse("Ruby,beginners\nRust\n", header_row: false)

    assert_equal [ "column_1", "column_2" ], result.variables
    assert_nil result.headers
    assert_equal [
      { "column_1" => "Ruby", "column_2" => "beginners" },
      { "column_1" => "Rust", "column_2" => "" }
    ], result.rows
  end

  test "reads from an IO" do
    result = TestSuiteCsv.parse(StringIO.new("topic\nRuby\n"), header_row: true)

    assert_equal [ { "topic" => "Ruby" } ], result.rows
  end

  test "turns headers into valid, unique variable names" do
    result = TestSuiteCsv.parse("Topic Name,2nd topic,Thème,,topic_name,Topic-Name,_id\na,b,c,d,e,f,g\n", header_row: true)

    assert_equal [ "Topic_Name", "_2nd_topic", "Theme", "column_4", "topic_name", "Topic_Name_2", "_id" ], result.variables
    assert_equal [ "Topic Name", "2nd topic", "Thème", "", "topic_name", "Topic-Name", "_id" ], result.headers
  end

  test "keeps quoted values that span lines" do
    result = TestSuiteCsv.parse(%(topic,notes\nRuby,"Line one\nLine two, with a comma"\n), header_row: true)

    assert_equal [ { "topic" => "Ruby", "notes" => "Line one\nLine two, with a comma" } ], result.rows
  end

  test "strips a UTF-8 byte order mark" do
    result = TestSuiteCsv.parse("﻿topic\nRuby\n", header_row: true)

    assert_equal [ "topic" ], result.variables
  end

  test "skips blank rows" do
    result = TestSuiteCsv.parse("\ntopic\n\nRuby\n,\n  \nRust\n", header_row: true)

    assert_equal [ { "topic" => "Ruby" }, { "topic" => "Rust" } ], result.rows
  end

  test "drops trailing columns without a header or values" do
    result = TestSuiteCsv.parse("topic,,\nRuby,,\nRust,\n", header_row: true)

    assert_equal [ "topic" ], result.variables
    assert_equal [ "topic" ], result.headers
    assert_equal [ { "topic" => "Ruby" }, { "topic" => "Rust" } ], result.rows
  end

  test "rejects rows with more values than there are columns" do
    error = assert_raises(TestSuiteCsv::Error) do
      TestSuiteCsv.parse("topic\nRuby\nRust,extra\n", header_row: true)
    end

    assert_equal "Line 3 has 2 values, but the CSV file only has 1 column", error.message
  end

  test "rejects malformed CSV" do
    error = assert_raises(TestSuiteCsv::Error) do
      TestSuiteCsv.parse(%(topic\n"Ruby\n), header_row: true)
    end

    assert_match(/\AThe CSV file could not be read/, error.message)
  end

  test "rejects files that are not UTF-8" do
    error = assert_raises(TestSuiteCsv::Error) do
      TestSuiteCsv.parse("topic\nTh\xE8me\n".b, header_row: true)
    end

    assert_equal "The CSV file must be UTF-8 encoded", error.message
  end

  test "rejects files without columns or test cases" do
    assert_parse_error("The CSV file has no columns", "\n\n", header_row: false)
    assert_parse_error("The CSV file has no test cases", "topic\n", header_row: true)
  end

  test "rejects files over the size, column, and row limits" do
    assert_parse_error(/larger than 5 MB/, "a" * (TestSuiteCsv::MAX_BYTES + 1), header_row: false)
    assert_parse_error(/at most 50 are supported/, ([ "x" ] * 51).join(","), header_row: false)
    assert_parse_error(/at most 1000 are supported/, "topic\n" + "Ruby\n" * 1_001, header_row: true)
  end

  private

  def assert_parse_error(message, input, header_row:)
    error = assert_raises(TestSuiteCsv::Error) { TestSuiteCsv.parse(input, header_row: header_row) }
    message.is_a?(Regexp) ? assert_match(message, error.message) : assert_equal(message, error.message)
  end
end
