class CollectionsController < ApplicationController
  before_action :set_collection, only: %i[show update destroy]

  def index
    @collections = Collection.includes(:prompts).order(:name, :id)
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
      @collections = Collection.includes(:prompts).order(:name, :id)
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
    if @collection.destroy
      redirect_to collections_path, notice: "Collection deleted."
    else
      redirect_to @collection, alert: "A collection cannot be deleted after it has been used to create a trial."
    end
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
    @has_unversioned_changes = @current_revision &&
      @current_revision.content_digest != CollectionRevision.content_digest_for(@collection, @prompts)
  end
end
