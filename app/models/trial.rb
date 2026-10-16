class Trial < ApplicationRecord
  STATUSES = {
    pending: "pending",
    running: "running",
    completed: "completed",
    failed: "failed"
  }.freeze

  belongs_to :collection
  has_many :responses, dependent: :destroy, inverse_of: :trial

  enum :status, STATUSES, validate: true

  validates :model, presence: true
end
