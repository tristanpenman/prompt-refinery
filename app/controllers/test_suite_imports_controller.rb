# Imports a test suite from a CSV file. Uploading creates a provisional test
# suite that is previewed here, then confirmed or discarded.
class TestSuiteImportsController < ApplicationController
  before_action :set_test_suite, only: %i[show update destroy]

  def create
    attributes = params.expect(test_suite_import: %i[file header_row])

    unless attributes[:file].respond_to?(:read)
      redirect_to test_suites_path, alert: "Choose a CSV file to import."
      return
    end

    test_suite = TestSuite.import_csv!(
      file: attributes[:file],
      header_row: ActiveModel::Type::Boolean.new.cast(attributes[:header_row]) || false
    )
    redirect_to test_suite_import_path(test_suite)
  rescue TestSuiteCsv::Error, ActiveRecord::RecordInvalid => error
    redirect_to test_suites_path, alert: "The CSV file could not be imported. #{error.message}"
  end

  def show
    prepare_show
  end

  def update
    attributes = params.expect(test_suite: [ :name, variables: {} ])
    @variable_names = attributes.fetch(:variables, {}).to_h

    @test_suite.confirm_import!(name: attributes[:name], variable_names: @variable_names)
    redirect_to @test_suite, notice: "Test suite imported."
  rescue ActiveRecord::RecordInvalid
    prepare_show
    render :show, status: :unprocessable_content
  end

  def destroy
    @test_suite.source_csv.purge
    @test_suite.destroy!
    redirect_to test_suites_path, notice: "Import discarded."
  end

  private

  def set_test_suite
    @test_suite = TestSuite.provisional.find(params[:id])
  end

  def prepare_show
    # A failed confirmation leaves the submitted changes on the suite, so the
    # preview is built from the saved variables.
    @variables = @test_suite.variables_in_database
    @variable_names ||= {}
    @headers = @test_suite.source_csv_headers
    @test_cases = @test_suite.test_cases.to_a
  end
end
