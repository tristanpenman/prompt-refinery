class Prompt < ApplicationRecord
  belongs_to :collection, inverse_of: :prompts
  has_many :responses, dependent: :restrict_with_error, inverse_of: :prompt
  has_many :prompt_revisions, dependent: :destroy, inverse_of: :prompt

  validates :name, presence: true
  validates :template, presence: true
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
