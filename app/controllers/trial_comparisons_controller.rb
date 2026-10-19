class TrialComparisonsController < ApplicationController
  before_action :set_trial

  def show
    if params[:baseline].present?
      load_comparison
    else
      load_candidates
    end
  end

  private

  def set_trial
    @trial = Trial.includes(:prompt_revision, :test_suite_revision).find(params[:id])
  end

  def candidate_trials
    test_case_ids = TestCaseRevision
      .joins(test_suite_revision_cases: :responses)
      .where(responses: { trial_id: @trial.id })
      .select(:test_case_id)

    Trial
      .includes(:prompt_revision, :test_suite_revision)
      .joins(responses: { test_suite_revision_case: :test_case_revision })
      .where(test_case_revisions: { test_case_id: test_case_ids })
      .where.not(id: @trial.id)
      .distinct
  end

  def load_candidates
    @comparison_trials = candidate_trials.order(created_at: :desc)
  end

  def load_comparison
    @baseline = candidate_trials.find(params[:baseline])

    baseline_responses = responses_for(@baseline).index_by { |response| response.test_case_revision.test_case_id }
    @comparisons = responses_for(@trial).filter_map do |current_response|
      baseline_response = baseline_responses[current_response.test_case_revision.test_case_id]
      next unless baseline_response

      {
        baseline_response: baseline_response,
        current_response: current_response
      }
    end
  end

  def responses_for(trial)
    trial.responses
      .joins(:test_suite_revision_case)
      .includes(test_suite_revision_case: :test_case_revision)
      .order("test_suite_revision_cases.position", "responses.id")
      .to_a
  end
end
