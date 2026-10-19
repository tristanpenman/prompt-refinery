class CollectionRevisionsController < ApplicationController
  def index
    @collection = Collection.find(params[:id])
    @current_prompts = @collection.prompts.to_a
    revisions = @collection.collection_revisions
      .includes(collection_revision_prompts: :prompt_revision)
      .order(version: :desc)
      .to_a
    @latest_revision = revisions.first
    @has_unrevised_changes = @latest_revision.nil? ||
      @latest_revision.content_digest != CollectionRevision.content_digest_for(@collection, @current_prompts)
    @current_revision_number = if @has_unrevised_changes
      @latest_revision&.version.to_i + 1
    else
      @latest_revision.version
    end
    @revisions = @has_unrevised_changes ? revisions : revisions.drop(1)
  end
end
