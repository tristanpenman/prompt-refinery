class Collection < ApplicationRecord
  has_many :prompts, -> { order(:position, :id) }, dependent: :destroy, inverse_of: :collection

  validates :name, presence: true
end
