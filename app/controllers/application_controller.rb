class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :accept_token_parameter
  before_action :require_authentication

  helper_method :authenticated?

  private

  def token_authenticator
    @token_authenticator ||= TokenAuthenticator.new
  end

  def authenticated?
    token_authenticator.valid?(cookies.encrypted[:prompt_refinery_auth_token])
  rescue TokenAuthenticator::ConfigurationError
    false
  end

  def accept_token_parameter
    return unless params[:token].present? && token_authenticator.valid?(params[:token])

    store_authentication_cookie(params[:token])
    redirect_to sanitized_request_path
  end

  def require_authentication
    redirect_to login_path(return_to: sanitized_request_path) unless authenticated?
  end

  def store_authentication_cookie(token)
    cookies.encrypted[:prompt_refinery_auth_token] = {
      value: token,
      expires: 1.year.from_now,
      httponly: true,
      same_site: :lax,
      secure: request.ssl?
    }
  end

  def safe_return_path
    path = params[:return_to]
    path if path.to_s.start_with?("/") && !path.to_s.start_with?("//")
  end

  def sanitized_request_path
    query = request.query_parameters.except("token").to_query
    query.present? ? "#{request.path}?#{query}" : request.path
  end
end
