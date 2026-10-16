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
    @trial = Trial.includes(:collection_revision).find(params[:id])
  end

  def load_candidates
    prompt_ids = @trial.responses.select(:prompt_id)
    @comparison_trials = Trial
      .includes(:collection_revision)
      .joins(:responses)
      .where(collection_id: @trial.collection_id, responses: { prompt_id: prompt_ids })
      .where.not(id: @trial.id)
      .distinct
      .order(created_at: :desc)
  end

  def load_comparison
    prompt_ids = @trial.responses.select(:prompt_id)
    @baseline = Trial
      .includes(:collection_revision)
      .joins(:responses)
      .where(collection_id: @trial.collection_id, responses: { prompt_id: prompt_ids })
      .where.not(id: @trial.id)
      .distinct
      .find(params[:baseline])

    baseline_responses = responses_for(@baseline).index_by(&:prompt_id)
    @comparisons = responses_for(@trial).filter_map do |current_response|
      baseline_response = baseline_responses[current_response.prompt_id]
      next unless baseline_response

      {
        baseline_response: baseline_response,
        current_response: current_response
      }
    end
  end

  def responses_for(trial)
    trial.responses
      .joins(collection_revision_prompt: :prompt_revision)
      .includes(collection_revision_prompt: :prompt_revision)
      .order("collection_revision_prompts.position", "responses.id")
      .to_a
  end
end
