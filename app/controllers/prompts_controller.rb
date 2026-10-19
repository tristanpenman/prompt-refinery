class PromptsController < ApplicationController
  before_action :set_prompt, only: %i[show update destroy unarchive]

  def index
    load_prompts
    @prompt = Prompt.new
  end

  def show
    prepare_show
  end

  def create
    @prompt = Prompt.new(prompt_params)

    if @prompt.save
      redirect_to @prompt, notice: "Prompt created."
    else
      load_prompts
      render :index, status: :unprocessable_content
    end
  end

  def update
    if @prompt.archived_at?
      redirect_to @prompt, alert: "Archived prompts are read-only. Unarchive this prompt to make changes."
      return
    end

    if @prompt.update(prompt_params)
      redirect_to @prompt, notice: "Prompt updated."
    else
      prepare_show
      render :show, status: :unprocessable_content
    end
  end

  def destroy
    @prompt.archive!
    redirect_to prompts_path, notice: "Prompt archived."
  end

  def unarchive
    @prompt.unarchive!
    redirect_to @prompt, notice: "Prompt unarchived."
  end

  private

  def set_prompt
    @prompt = Prompt.find(params[:id])
  end

  def prompt_params
    params.expect(prompt: %i[name template])
  end

  def prepare_show
    @current_revision = @prompt.prompt_revisions.order(version: :desc).first
    @has_unrevised_changes = @current_revision &&
      @current_revision.content_digest != PromptRevision.content_digest_for(@prompt)
  end

  def load_prompts
    @show_archived = params[:archived] == "true"
    prompt_scope = @show_archived ? Prompt.archived : Prompt.active
    @prompts = prompt_scope.includes(:prompt_revisions).order(:name, :id)
    @prompt_rows = @prompts.map do |prompt|
      latest_revision = prompt.prompt_revisions.max_by(&:version)

      {
        prompt: prompt,
        revision: latest_revision&.version,
        draft: latest_revision.nil? || latest_revision.content_digest != PromptRevision.content_digest_for(prompt)
      }
    end
  end
end
