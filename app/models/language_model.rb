# == Schema Information
#
# Table name: language_models
# Database name: primary
#
#  id                       :integer          not null, primary key
#  available                :boolean          default(TRUE), not null
#  details                  :json             not null
#  name                     :string           not null
#  refreshed_at             :datetime         not null
#  size                     :bigint
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  backend_id               :integer          not null
#  language_model_family_id :integer          not null
#
# Indexes
#
#  index_language_models_on_backend_id                (backend_id)
#  index_language_models_on_backend_id_and_name       (backend_id,name) UNIQUE
#  index_language_models_on_language_model_family_id  (language_model_family_id)
#
# Foreign Keys
#
#  backend_id                (backend_id => backends.id)
#  language_model_family_id  (language_model_family_id => language_model_families.id)
#
class LanguageModel < ApplicationRecord
  belongs_to :backend, inverse_of: :language_models
  belongs_to :language_model_family, inverse_of: :language_models

  before_validation :assign_derived_family, if: -> { language_model_family.nil? }
  before_validation -> { self.refreshed_at ||= Time.current }, on: :create
  after_update -> { destroy_family_if_empty(language_model_family_id_before_last_save) },
    if: :saved_change_to_language_model_family_id?
  after_destroy -> { destroy_family_if_empty(language_model_family_id) }

  validates :name, presence: true, uniqueness: { scope: :backend_id }

  scope :available, -> { where(available: true) }

  def language_model_family_name
    language_model_family&.name
  end

  def language_model_family_name=(family_name)
    family_name = family_name.to_s.strip
    self.language_model_family = family_name.present? ? LanguageModelFamily.find_or_initialize_by(name: family_name) : nil
  end

  def self.family_name_for(model_name)
    model_name.to_s.strip.split(":", 2).first.presence
  end

  private

  def assign_derived_family
    family_name = self.class.family_name_for(name)
    self.language_model_family = LanguageModelFamily.find_or_create_by!(name: family_name) if family_name
  end

  def destroy_family_if_empty(family_id)
    LanguageModelFamily.where(id: family_id).where.missing(:language_models).destroy_all
  end
end
