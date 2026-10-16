class CollectionVersionsController < ApplicationController
  def index
    @collection = Collection.find(params[:id])
    @current_prompts = @collection.prompts.to_a
    versions = @collection.collection_revisions
      .includes(:trials, collection_revision_prompts: :prompt_revision)
      .order(version: :desc)
      .to_a
    @latest_revision = versions.first
    @has_unversioned_changes = @latest_revision.nil? ||
      @latest_revision.content_digest != CollectionRevision.content_digest_for(@collection, @current_prompts)
    @current_version = if @has_unversioned_changes
      @latest_revision&.version.to_i + 1
    else
      @latest_revision.version
    end
    @versions = @has_unversioned_changes ? versions : versions.drop(1)
  end
end
