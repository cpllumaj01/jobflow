class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[ new create ]
  rate_limit to: 10, within: 3.minutes, name: "ip", only: :create,
    store: AuthenticationRateLimitStore.new(cache_store), with: -> { redirect_to new_session_path, alert: "Try again later." }
  rate_limit to: 10, within: 15.minutes, name: "email", only: :create,
    by: -> { Digest::SHA256.hexdigest(params.permit(:email_address)[:email_address].to_s.strip.downcase) },
    store: AuthenticationRateLimitStore.new(cache_store),
    with: -> { redirect_to new_session_path, alert: "Try again later." }

  def new
  end

  def create
    session.delete(:two_factor_login_token)
    credentials = params.permit(:email_address, :password)

    if user = User.authenticate_by(email_address: credentials[:email_address], password: credentials[:password])
      authenticated_digest = user.password_digest
      user.with_lock do
        # Serialize session creation with password and 2FA changes, and reject
        # credentials changed since authenticate_by performed its password check.
        if user.password_digest != authenticated_digest
          redirect_to new_session_path, alert: "Try another email address or password."
        elsif user.two_factor_enabled?
          begin_two_factor_challenge(user, return_to: after_authentication_url)
          redirect_to new_two_factor_challenge_path
        else
          return_to = after_authentication_url
          start_new_session_for user
          redirect_to return_to
        end
      end
    else
      redirect_to new_session_path, alert: "Try another email address or password."
    end
  end

  def destroy
    terminate_session
    redirect_to new_session_path, status: :see_other
  end
end
