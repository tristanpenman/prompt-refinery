# Serves the CSV file a test suite was imported from. Active Storage's own
# routes are disabled because they bypass authentication.
class TestSuiteCsvsController < ApplicationController
  def show
    source_csv = TestSuite.find(params[:id]).source_csv
    raise ActiveRecord::RecordNotFound, "Test suite has no source CSV" unless source_csv.attached?

    send_data source_csv.download,
      filename: source_csv.filename.to_s,
      type: "text/csv",
      disposition: :attachment
  end
end
