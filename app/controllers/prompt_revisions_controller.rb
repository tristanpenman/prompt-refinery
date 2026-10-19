class PromptRevisionsController < ApplicationController
  def index
    @prompt = Prompt.find(params[:id])
    revisions = @prompt.prompt_revisions.includes(:trials).order(version: :desc).to_a
    @latest_revision = revisions.first
    @has_unrevised_changes = @latest_revision.nil? ||
      @latest_revision.content_digest != PromptRevision.content_digest_for(@prompt)
    @current_revision_number = if @has_unrevised_changes
      @latest_revision&.version.to_i + 1
    else
      @latest_revision.version
    end
    @revisions = @has_unrevised_changes ? revisions : revisions.drop(1)
  end
end
