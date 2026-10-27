class TwoFactorChallengesController < ApplicationController
  allow_unauthenticated_access
  before_action :prevent_caching
  before_action :set_pending_user, only: %i[new create]
  rate_limit to: 10, within: 5.minutes, name: "ip", only: :create,
    store: AuthenticationRateLimitStore.new(cache_store)
  rate_limit to: 10, within: 5.minutes, name: "account", only: :create,
    scope: "second_factor", by: -> { @user.id }, store: AuthenticationRateLimitStore.new(cache_store)

  def new
  end

  def create
    @user.with_lock do
      # Recheck under the same lock as code consumption and session creation.
      # This also rejects a completed challenge replayed from an old cookie.
      if !User.find_by_token_for(:two_factor_login, session[:two_factor_login_token])
        expire_challenge
      elsif @user.consume_two_factor!(params.permit(:verification_code)[:verification_code])
        return_to = after_authentication_url
        start_new_session_for @user
        redirect_to return_to
      else
        flash.now[:alert] = "Invalid or already used code. Try a current authenticator code or an unused recovery code."
        render :new, status: :unprocessable_entity
      end
    end
  end

  def destroy
    token = session[:two_factor_login_token]
    if token && (user = User.find_by_token_for(:two_factor_login, token))
      user.with_lock do
        # Recheck after locking: an already canceled or completed challenge
        # must not invalidate a fresh challenge while this request waits.
        if User.where(id: user.id).find_by_token_for(:two_factor_login, token)
          user.increment!(:two_factor_challenge_version)
        end
      end
    end
    reset_session
    redirect_to new_session_path, status: :see_other
  end

  private
    def prevent_caching
      no_store
      response.set_header("Referrer-Policy", "no-referrer")
    end

    def set_pending_user
      token = session[:two_factor_login_token]
      @user = User.find_by_token_for(:two_factor_login, token) if token
      expire_challenge unless @user&.two_factor_enabled?
    end

    def expire_challenge
      reset_session
      redirect_to new_session_path, alert: "Sign-in verification expired. Sign in again."
    end
end
