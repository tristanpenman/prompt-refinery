class SessionsController < ApplicationController
  skip_before_action :accept_token_parameter
  skip_before_action :require_authentication

  def new
    redirect_to root_path if authenticated?
  end

  def create
    if token_authenticator.valid?(params[:token])
      store_authentication_cookie(params[:token])
      redirect_to safe_return_path || root_path
    else
      flash.now[:alert] = if token_authenticator.configured?
        "The token is incorrect."
      else
        "Authentication has not been configured. Set RAILS_AUTH_TOKEN and restart the app."
      end
      render :new, formats: :html, status: :unprocessable_content
    end
  rescue TokenAuthenticator::ConfigurationError => error
    flash.now[:alert] = error.message
    render :new, formats: :html, status: :unprocessable_content
  end

  def destroy
    cookies.delete(:prompt_refinery_auth_token)
    redirect_to login_path
  end
end
