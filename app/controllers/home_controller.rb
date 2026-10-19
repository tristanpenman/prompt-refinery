class HomeController < ApplicationController
  def index
    @prompts = Prompt.active.order(updated_at: :desc).limit(3)
    @test_suites = TestSuite.active.order(updated_at: :desc).limit(3)
    @trials = Trial.includes(:prompt_revision, :test_suite_revision).order(created_at: :desc).limit(3)
  end
end
