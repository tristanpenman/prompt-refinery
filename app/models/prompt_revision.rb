require "digest"
# == Schema Information
#
# Table name: prompt_revisions
# Database name: primary
#
#  id             :integer          not null, primary key
#  content_digest :string           not null
#  name           :string           not null
#  template       :text             not null
#  version        :integer          not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  prompt_id      :integer          not null
#
# Indexes
#
#  index_prompt_revisions_on_prompt_id                     (prompt_id)
#  index_prompt_revisions_on_prompt_id_and_content_digest  (prompt_id,content_digest) UNIQUE
#  index_prompt_revisions_on_prompt_id_and_version         (prompt_id,version) UNIQUE
#
# Foreign Keys
#
#  prompt_id  (prompt_id => prompts.id)
#
class PromptRevision < ApplicationRecord
  belongs_to :prompt, inverse_of: :prompt_revisions
  has_many :trials, dependent: :restrict_with_error, inverse_of: :prompt_revision

  validates :version, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :prompt_id }
  validates :name, :template, :content_digest, presence: true
  validates :content_digest, uniqueness: { scope: :prompt_id }

  before_update :prevent_changes

  def self.capture!(prompt)
    prompt.with_lock do
      digest = content_digest_for(prompt)
      find_by(prompt: prompt, content_digest: digest) || create!(
        prompt: prompt,
        version: where(prompt: prompt).maximum(:version).to_i + 1,
        name: prompt.name,
        template: prompt.template,
        content_digest: digest
      )
    end
  end

  def self.content_digest_for(prompt)
    Digest::SHA256.hexdigest([ prompt.name, prompt.template ].to_json)
  end

  private

  def prevent_changes
    errors.add(:base, "Prompt revisions are immutable")
    throw :abort
  end
end
