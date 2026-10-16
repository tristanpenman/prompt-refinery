class CollectionsController < ApplicationController
  before_action :set_collection, only: %i[show update destroy]

  def index
    load_collections
    @collection = Collection.new
  end

  def show
    prepare_show
  end

  def create
    @collection = Collection.new(collection_params)

    if @collection.save
      redirect_to @collection, notice: "Collection created."
    else
      load_collections
      render :index, status: :unprocessable_content
    end
  end

  def update
    if @collection.update(collection_params)
      redirect_to @collection, notice: "Collection updated."
    else
      prepare_show
      render :show, status: :unprocessable_content
    end
  end

  def destroy
    @collection.archive!
    redirect_to collections_path, notice: "Collection archived."
  end

  private

  def set_collection
    @collection = Collection.find(params[:id])
  end

  def collection_params
    params.expect(collection: [ :name ])
  end

  def next_prompt_position
    (@collection.prompts.maximum(:position) || -1) + 1
  end

  def prepare_show
    @prompts = @collection.prompts.to_a
    @prompt = @collection.prompts.build(position: next_prompt_position)
    @current_revision = @collection.collection_revisions.order(version: :desc).first
    @has_unrevised_changes = @current_revision &&
      @current_revision.content_digest != CollectionRevision.content_digest_for(@collection, @prompts)
  end

  def load_collections
    @collections = Collection.active.includes(:prompts, :collection_revisions).order(:name, :id)
    @collection_rows = @collections.map do |collection|
      latest_revision = collection.collection_revisions.max_by(&:version)
      has_draft = latest_revision.nil? ||
        latest_revision.content_digest != CollectionRevision.content_digest_for(collection, collection.prompts.to_a)

      {
        collection: collection,
        revision: latest_revision&.version,
        draft: has_draft
      }
    end
  end
end
