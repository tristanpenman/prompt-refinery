require "test_helper"

class TestSuiteCsvsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_encrypted_token = ENV["RAILS_AUTH_TOKEN"]
    ENV["RAILS_AUTH_TOKEN"] = TokenAuthenticator.encrypt("test-token")
    post login_path, params: { token: "test-token" }
  end

  teardown do
    ENV["RAILS_AUTH_TOKEN"] = @original_encrypted_token
  end

  test "the test suite page links to the original CSV of an imported test suite" do
    test_suite = import_csv("topic\nRuby\n", filename: "topics.csv")
    test_suite.confirm_import!(name: "Topics")

    get test_suite_path(test_suite)

    assert_select "section.editor-card h2", text: "Source CSV"
    assert_select "section.editor-card p", text: /imported from topics\.csv/
    assert_select "a[href='#{csv_test_suite_path(test_suite)}'][data-turbo=false]", text: "Download original CSV"
  end

  test "the test suite page has no download link for a test suite created by hand" do
    test_suite = create_test_suite

    get test_suite_path(test_suite)

    assert_select "a[href='#{csv_test_suite_path(test_suite)}']", count: 0
  end

  test "downloads the original CSV file" do
    contents = "Topic Name,audience\nRuby,beginners\n"
    test_suite = import_csv(contents, filename: "topics.csv")
    test_suite.confirm_import!(name: "Topics", variable_names: { "Topic_Name" => "topic" })

    get csv_test_suite_path(test_suite)

    assert_response :success
    assert_equal contents, response.body
    assert_equal "text/csv", response.media_type
    assert_match(/\Aattachment; filename="topics\.csv"/, response.headers["Content-Disposition"])
  end

  test "downloads the CSV file of an archived test suite" do
    test_suite = import_csv("topic\nRuby\n")
    test_suite.confirm_import!(name: "Topics")
    test_suite.archive!

    get csv_test_suite_path(test_suite)

    assert_response :success
  end

  test "returns not found for a test suite without a CSV file" do
    get csv_test_suite_path(create_test_suite)

    assert_response :not_found
  end

  test "requires authentication" do
    test_suite = import_csv("topic\nRuby\n")
    delete logout_path

    get csv_test_suite_path(test_suite)

    assert_redirected_to login_path(return_to: csv_test_suite_path(test_suite))
  end

  private

  def import_csv(contents, filename: "import.csv")
    file = Rack::Test::UploadedFile.new(StringIO.new(contents), "text/csv", original_filename: filename)
    TestSuite.import_csv!(file: file, header_row: true)
  end
end
