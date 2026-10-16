class TokenAuthenticator
  PURPOSE = "prompt_refinery authentication token"

  class ConfigurationError < StandardError; end

  def self.encrypt(token)
    encryptor.encrypt_and_sign(token, purpose: PURPOSE)
  end

  def self.decrypt(encrypted_token)
    encryptor.decrypt_and_verify(encrypted_token, purpose: PURPOSE)
  end

  def initialize(encrypted_token: ENV["RAILS_AUTH_TOKEN"])
    @encrypted_token = encrypted_token
  end

  def configured?
    encrypted_token.present?
  end

  def valid?(candidate)
    return false if candidate.blank? || !configured?

    expected = self.class.decrypt(encrypted_token)
    ActiveSupport::SecurityUtils.secure_compare(
      OpenSSL::Digest::SHA256.hexdigest(candidate),
      OpenSSL::Digest::SHA256.hexdigest(expected)
    )
  rescue ActiveSupport::MessageEncryptor::InvalidMessage
    raise ConfigurationError, "RAILS_AUTH_TOKEN is invalid or was encrypted with a different secret key"
  end

  class << self
    private

    def encryptor
      key = Rails.application.key_generator.generate_key(PURPOSE, 32)
      ActiveSupport::MessageEncryptor.new(key)
    end
  end

  private

  attr_reader :encrypted_token
end
