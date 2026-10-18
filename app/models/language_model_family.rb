# == Schema Information
#
# Table name: language_model_families
# Database name: primary
#
#  id         :integer          not null, primary key
#  name       :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_language_model_families_on_name  (name) UNIQUE
#
class LanguageModelFamily < ApplicationRecord
  has_many :language_models, dependent: :restrict_with_error, inverse_of: :language_model_family
  has_many :backends, -> { distinct }, through: :language_models

  validates :name, presence: true, uniqueness: true
end
