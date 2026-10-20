require "test_helper"

class TestSuiteImportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_encrypted_token = ENV["RAILS_AUTH_TOKEN"]
    ENV["RAILS_AUTH_TOKEN"] = TokenAuthenticator.encrypt("test-token")
    post login_path, params: { token: "test-token" }
  end

  teardown do
    ENV["RAILS_AUTH_TOKEN"] = @original_encrypted_token
  end

  test "the test suites page offers a CSV import" do
    get test_suites_path

    assert_select "form[action='#{test_suite_imports_path}'][enctype='multipart/form-data']" do
      assert_select "input[type=file][name='test_suite_import[file]']"
      assert_select "input[type=checkbox][name='test_suite_import[header_row]'][checked]"
    end
  end

  test "uploading a CSV file creates a provisional test suite and shows its preview" do
    assert_difference -> { TestSuite.provisional.count } => 1, -> { TestCase.count } => 2 do
      post test_suite_imports_path, params: {
        test_suite_import: { file: csv_upload("Topic Name,audience\nRuby,beginners\nRust,experts\n", filename: "topics.csv"), header_row: "1" }
      }
    end

    test_suite = TestSuite.provisional.last
    assert_redirected_to test_suite_import_path(test_suite)
    assert_equal "topics.csv", test_suite.source_csv.filename.to_s

    follow_redirect!
    assert_response :success
    assert_select "h1", text: /topics\s+Provisional/
    assert_select "header p", text: /topics\.csv\s+· 2 variables\s+· 2 test cases\s+· Variable names read from the header row/
    assert_select "input[name='test_suite[name]'][value='topics']"
    assert_select "label", text: /Variable 1\s+from column\s+Topic Name/
    assert_select "input[name='test_suite[variables][Topic_Name]'][value='Topic_Name']"
    assert_select "input[name='test_suite[variables][audience]'][value='audience']"
    assert_select ".import-preview tbody tr", count: 2
    assert_select ".import-preview tbody tr", text: /Ruby\s+beginners/
  end

  test "uploading a CSV file without a header row" do
    post test_suite_imports_path, params: { test_suite_import: { file: csv_upload("Ruby,beginners\n"), header_row: "0" } }

    test_suite = TestSuite.provisional.last
    assert_equal [ "column_1", "column_2" ], test_suite.variables

    follow_redirect!
    assert_select "header p", text: /No header row/
    assert_select "label", text: /from column/, count: 0
  end

  test "a CSV file that can't be imported redirects back with the reason" do
    assert_no_difference -> { TestSuite.count } do
      post test_suite_imports_path, params: { test_suite_import: { file: csv_upload("topic\nRuby,extra\n"), header_row: "1" } }
    end

    assert_redirected_to test_suites_path
    assert_equal "The CSV file could not be imported. Line 2 has 2 values, but the CSV file only has 1 column", flash[:alert]
  end

  test "uploading without a file redirects back" do
    post test_suite_imports_path, params: { test_suite_import: { header_row: "1" } }

    assert_redirected_to test_suites_path
    assert_equal "Choose a CSV file to import.", flash[:alert]
  end

  test "confirming an import creates the test suite" do
    test_suite = import_csv("a,b\nRuby,beginners\n")

    patch test_suite_import_path(test_suite), params: {
      test_suite: { name: "Topics", variables: { "a" => "topic", "b" => "audience" } }
    }

    assert_redirected_to test_suite_path(test_suite)
    assert_equal "Test suite imported.", flash[:notice]
    test_suite.reload
    assert_not test_suite.provisional?
    assert_equal "Topics", test_suite.name
    assert_equal [ { "topic" => "Ruby", "audience" => "beginners" } ], test_suite.test_cases.map(&:values)
  end

  test "an invalid confirmation shows the preview with errors" do
    test_suite = import_csv("a,b\nRuby,beginners\n")

    patch test_suite_import_path(test_suite), params: {
      test_suite: { name: "", variables: { "a" => "topic", "b" => "two words" } }
    }

    assert_response :unprocessable_content
    assert_select ".form-error li", text: "Name can't be blank"
    assert_select ".form-error li", text: "Variables must be names made of letters, digits, and underscores"
    assert_select "input[name='test_suite[variables][b]'][value='two words']"
    assert_select ".import-preview th", text: "{{b}}"
    assert test_suite.reload.provisional?
  end

  test "discarding an import deletes the test suite and its CSV file" do
    test_suite = import_csv("topic\nRuby\n")

    assert_difference -> { TestSuite.count } => -1, -> { TestCase.count } => -1, -> { ActiveStorage::Blob.count } => -1 do
      delete test_suite_import_path(test_suite)
    end

    assert_redirected_to test_suites_path
    assert_equal "Import discarded.", flash[:notice]
  end

  test "confirmed test suites are not available as imports" do
    test_suite = create_test_suite

    get test_suite_import_path(test_suite)
    assert_response :not_found

    delete test_suite_import_path(test_suite)
    assert_response :not_found
    assert TestSuite.exists?(test_suite.id)
  end

  test "provisional test suites are hidden from the test suite list and redirect to their preview" do
    test_suite = import_csv("topic\nRuby\n", filename: "hidden.csv")

    get test_suites_path
    assert_select "td", text: "hidden", count: 0

    get test_suite_path(test_suite)
    assert_redirected_to test_suite_import_path(test_suite)

    patch test_suite_path(test_suite), params: { test_suite: { name: "Changed" } }
    assert_redirected_to test_suite_import_path(test_suite)
    assert_equal "hidden", test_suite.reload.name
  end

  test "requires authentication" do
    test_suite = import_csv("topic\nRuby\n")
    delete logout_path

    get test_suite_import_path(test_suite)
    assert_redirected_to login_path(return_to: test_suite_import_path(test_suite))

    post test_suite_imports_path, params: { test_suite_import: { file: csv_upload("topic\nRuby\n"), header_row: "1" } }
    assert_redirected_to login_path(return_to: test_suite_imports_path)
  end

  private

  # Posting a StringIO upload makes rack-test warn about frozen strings, so write a file.
  def csv_upload(contents, filename: "import.csv")
    file = Tempfile.new([ "import", ".csv" ])
    file.write(contents)
    file.close
    Rack::Test::UploadedFile.new(file.path, "text/csv", original_filename: filename)
  end

  def import_csv(contents, filename: "import.csv")
    TestSuite.import_csv!(file: csv_upload(contents, filename: filename), header_row: true)
  end
end
