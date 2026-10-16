class Prompt < ApplicationRecord
  belongs_to :collection, inverse_of: :prompts

  validates :name, presence: true
  validates :template, presence: true
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
