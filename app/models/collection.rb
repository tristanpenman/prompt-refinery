class Collection < ApplicationRecord
  has_many :trials, dependent: :restrict_with_error, inverse_of: :collection
  has_many :collection_revisions, dependent: :destroy, inverse_of: :collection
  has_many :prompts, -> { order(:position, :id) }, dependent: :destroy, inverse_of: :collection

  validates :name, presence: true
end
