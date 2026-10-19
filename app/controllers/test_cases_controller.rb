class TestCasesController < ApplicationController
  before_action :set_test_suite
  before_action :ensure_test_suite_active
  before_action :set_test_case, only: %i[update destroy]

  def create
    @test_case = @test_suite.test_cases.build(test_case_params)

    if @test_case.save
      redirect_to @test_suite, notice: "Test case added."
    else
      redirect_to @test_suite, alert: @test_case.errors.full_messages.to_sentence
    end
  end

  def update
    if @test_case.update(test_case_params)
      redirect_to @test_suite, notice: "Test case updated."
    else
      redirect_to @test_suite, alert: @test_case.errors.full_messages.to_sentence
    end
  end

  def destroy
    @test_case.soft_delete!
    redirect_to @test_suite, notice: "Test case deleted."
  end

  private

  def set_test_suite
    @test_suite = TestSuite.find(params[:test_suite_id])
  end

  def set_test_case
    @test_case = @test_suite.test_cases.find(params[:id])
  end

  def ensure_test_suite_active
    return unless @test_suite.archived_at?

    redirect_to @test_suite, alert: "Archived test suites are read-only. Unarchive this test suite to make changes."
  end

  def test_case_params
    params.expect(test_case: [ :position, values: {} ])
  end
end
