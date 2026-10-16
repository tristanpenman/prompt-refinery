require "digest"

class PromptRevision < ApplicationRecord
  belongs_to :prompt, inverse_of: :prompt_revisions
  has_many :collection_revision_prompts, dependent: :restrict_with_error, inverse_of: :prompt_revision

  validates :version, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :prompt_id }
  validates :name, :template, :content_digest, presence: true
  validates :content_digest, uniqueness: { scope: :prompt_id }

  before_update :prevent_changes

  def self.capture!(prompt)
    prompt.with_lock do
      digest = Digest::SHA256.hexdigest([ prompt.name, prompt.template ].to_json)
      find_by(prompt: prompt, content_digest: digest) || create!(
        prompt: prompt,
        version: where(prompt: prompt).maximum(:version).to_i + 1,
        name: prompt.name,
        template: prompt.template,
        content_digest: digest
      )
    end
  end

  private

  def prevent_changes
    errors.add(:base, "Prompt revisions are immutable")
    throw :abort
  end
end
