namespace :prompt_refinery do
  desc "Encrypt a plaintext authentication token for RAILS_AUTH_TOKEN"
  task encrypt_token: :environment do
    require "io/console"

    token = $stdin.getpass("Token: ")
    abort "Token cannot be empty" if token.blank?

    puts TokenAuthenticator.encrypt(token)
  end
end
