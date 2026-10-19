class HomeController < ApplicationController
  def index
    @collections = Collection.active.order(updated_at: :desc).limit(3)
    @test_suites = TestSuite.active.order(updated_at: :desc).limit(3)
    @trials = Trial.includes(:collection).order(created_at: :desc).limit(3)
  end
end
