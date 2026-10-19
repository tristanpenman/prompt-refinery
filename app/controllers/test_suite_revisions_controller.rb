class TestSuiteRevisionsController < ApplicationController
  def index
    @test_suite = TestSuite.find(params[:id])
    @current_test_cases = @test_suite.test_cases.to_a
    revisions = @test_suite.test_suite_revisions
      .includes(test_suite_revision_cases: :test_case_revision)
      .order(version: :desc)
      .to_a
    @latest_revision = revisions.first
    @has_unrevised_changes = @latest_revision.nil? ||
      @latest_revision.content_digest != TestSuiteRevision.content_digest_for(@test_suite, @current_test_cases)
    @current_revision_number = if @has_unrevised_changes
      @latest_revision&.version.to_i + 1
    else
      @latest_revision.version
    end
    @revisions = @has_unrevised_changes ? revisions : revisions.drop(1)
  end
end
