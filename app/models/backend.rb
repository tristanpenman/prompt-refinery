require "uri"

# == Schema Information
#
# Table name: backends
# Database name: primary
#
#  id         :integer          not null, primary key
#  adapter    :string           default("ollama"), not null
#  base_url   :string           not null
#  enabled    :boolean          default(TRUE), not null
#  name       :string           not null
#  system     :boolean          default(FALSE), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_backends_on_name    (name) UNIQUE
#  index_backends_on_system  (system) UNIQUE WHERE system = 1
#
class Backend < ApplicationRecord
  ADAPTERS = %w[ollama].freeze
  DEFAULT_NAME = "Local Ollama"
  DEFAULT_BASE_URL = "http://ollama:11434"

  scope :enabled, -> { where(enabled: true) }

  has_many :trials, dependent: :restrict_with_error, inverse_of: :backend

  before_validation :normalize_base_url
  before_destroy :prevent_system_backend_destruction

  validates :name, presence: true, uniqueness: true
  validates :base_url, presence: true
  validates :adapter, presence: true, inclusion: { in: ADAPTERS }
  validate :base_url_is_valid
  validate :system_backend_cannot_be_demoted, on: :update

  def self.ensure_system_default!(base_url: ENV.fetch("OLLAMA_URL", DEFAULT_BASE_URL))
    transaction do
      backend = lock.find_by(system: true) || lock.find_or_initialize_by(name: DEFAULT_NAME)
      existing_system_backend = backend.persisted? && backend.system?
      backend.name ||= DEFAULT_NAME
      backend.assign_attributes(base_url: base_url, adapter: "ollama", system: true)
      backend.enabled = true unless existing_system_backend
      backend.save!
      backend
    end
  end

  def self.system_default
    find_by!(system: true)
  end

  private

  def normalize_base_url
    self.base_url = base_url.to_s.strip.sub(%r{/+\z}, "") if base_url.present?
  end

  def base_url_is_valid
    return if base_url.blank?

    uri = URI.parse(base_url)
    errors.add(:base_url, "must use HTTP or HTTPS") unless uri.is_a?(URI::HTTP)
    errors.add(:base_url, "must include a host") if uri.host.blank?
    errors.add(:base_url, "must not include credentials") if uri.userinfo.present?
    errors.add(:base_url, "must not include a query") if uri.query.present?
    errors.add(:base_url, "must not include a fragment") if uri.fragment.present?
  rescue URI::InvalidURIError
    errors.add(:base_url, "is not a valid URL")
  end

  def system_backend_cannot_be_demoted
    errors.add(:system, "cannot be removed from the system backend") if system_in_database && !system?
  end

  def prevent_system_backend_destruction
    return unless system? || system_in_database

    errors.add(:base, "The system backend cannot be deleted")
    throw :abort
  end
end
