class TestSuitesController < ApplicationController
  before_action :set_test_suite, only: %i[show update destroy unarchive]

  def index
    load_test_suites
    @test_suite = TestSuite.new
  end

  def show
    prepare_show
  end

  def create
    @test_suite = TestSuite.new(test_suite_params)

    if @test_suite.save
      redirect_to @test_suite, notice: "Test suite created."
    else
      load_test_suites
      render :index, status: :unprocessable_content
    end
  end

  def update
    if @test_suite.archived_at?
      redirect_to @test_suite, alert: "Archived test suites are read-only. Unarchive this test suite to make changes."
      return
    end

    if @test_suite.update(test_suite_params)
      redirect_to @test_suite, notice: "Test suite updated."
    else
      prepare_show
      render :show, status: :unprocessable_content
    end
  end

  def destroy
    @test_suite.archive!
    redirect_to test_suites_path, notice: "Test suite archived."
  end

  def unarchive
    @test_suite.unarchive!
    redirect_to @test_suite, notice: "Test suite unarchived."
  end

  private

  def set_test_suite
    @test_suite = TestSuite.find(params[:id])
  end

  def test_suite_params
    params.expect(test_suite: %i[name variable_list])
  end

  def next_test_case_position
    (@test_suite.test_cases.maximum(:position) || -1) + 1
  end

  def prepare_show
    @test_cases = @test_suite.test_cases.to_a
    @current_revision = @test_suite.test_suite_revisions.order(version: :desc).first
    @has_unrevised_changes = @current_revision &&
      @current_revision.content_digest != TestSuiteRevision.content_digest_for(@test_suite, @test_cases)
    # Validation errors leave unsaved variables on the suite, so forms are built from the saved ones.
    @variables = @test_suite.variables_in_database
    return if @test_suite.archived_at? || @variables.empty?

    @test_case = @test_suite.test_cases.build(
      position: next_test_case_position,
      values: @variables.index_with { "" }
    )
  end

  def load_test_suites
    @show_archived = params[:archived] == "true"
    test_suite_scope = @show_archived ? TestSuite.archived : TestSuite.active
    @test_suites = test_suite_scope.includes(:test_cases, :test_suite_revisions).order(:name, :id)
    @test_suite_rows = @test_suites.map do |test_suite|
      latest_revision = test_suite.test_suite_revisions.max_by(&:version)
      has_draft = latest_revision.nil? ||
        latest_revision.content_digest != TestSuiteRevision.content_digest_for(test_suite, test_suite.test_cases.to_a)

      {
        test_suite: test_suite,
        revision: latest_revision&.version,
        draft: has_draft
      }
    end
  end
end
