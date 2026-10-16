class CollectionPromptsController < ApplicationController
  before_action :set_collection
  before_action :set_prompt, only: %i[update destroy]

  def create
    @prompt = @collection.prompts.build(prompt_params)

    if @prompt.save
      redirect_to @collection, notice: "Prompt added."
    else
      redirect_to @collection, alert: @prompt.errors.full_messages.to_sentence
    end
  end

  def update
    if @prompt.update(prompt_params)
      redirect_to @collection, notice: "Prompt updated."
    else
      redirect_to @collection, alert: @prompt.errors.full_messages.to_sentence
    end
  end

  def destroy
    @prompt.soft_delete!
    redirect_to @collection, notice: "Prompt deleted."
  end

  private

  def set_collection
    @collection = Collection.find(params[:collection_id])
  end

  def set_prompt
    @prompt = @collection.prompts.find(params[:id])
  end

  def prompt_params
    params.expect(prompt: %i[name template position])
  end
end
