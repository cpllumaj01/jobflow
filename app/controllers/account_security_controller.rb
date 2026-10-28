class AccountSecurityController < ApplicationController
  before_action :prevent_caching
  around_action :lock_account, except: :show
  rate_limit to: 10, within: 5.minutes, name: "ip", except: :show,
    store: AuthenticationRateLimitStore.new(cache_store)
  rate_limit to: 10, within: 5.minutes, name: "account", except: :show,
    scope: "second_factor", by: -> { Current.user.id }, store: AuthenticationRateLimitStore.new(cache_store)

  def show
  end

  def setup
    session.delete(:two_factor_setup)
    if Current.user.two_factor_enabled? || !Current.user.authenticate(security_params[:password].to_s)
      redirect_to account_security_path, alert: "Unable to start setup. Check your current password and security settings."
    else
      # Both pending and active secrets use Active Record Encryption. Keep
      # plaintext secrets out of browser sessions and Rails exception dumps.
      @secret = ROTP::Base32.random
      Current.user.update!(otp_setup_secret: @secret)
      session[:two_factor_setup] = {
        token: Current.user.generate_token_for(:two_factor_setup),
        session_id: Current.session.id
      }
      render :setup
    end
  end

  def enable
    pending = session[:two_factor_setup]
    if !pending || pending["session_id"] != Current.session.id ||
        !User.where(id: Current.user.id).find_by_token_for(:two_factor_setup, pending["token"])
      session.delete(:two_factor_setup)
      redirect_to account_security_path, alert: "Authenticator setup expired. Start setup again."
    else
      @secret = Current.user.otp_setup_secret
      # Password confirmation was completed when issuing the expiring setup
      # token; its fingerprint also invalidates setup after a password change.
      @recovery_codes = Current.user.enable_two_factor!(
        secret: @secret, code: security_params[:verification_code]
      )
      if @recovery_codes
        start_new_session_for Current.user
        render :recovery_codes
      else
        flash.now[:alert] = "Enter a valid authenticator code."
        render :setup, status: :unprocessable_entity
      end
    end
  end

  def cancel_setup
    Current.user.update!(otp_setup_secret: nil)
    session.delete(:two_factor_setup)
    redirect_to account_security_path, status: :see_other
  end

  def recovery_codes
    @recovery_codes = Current.user.regenerate_recovery_codes!(password: security_params[:password], code: security_params[:verification_code])
    if @recovery_codes
      start_new_session_for Current.user
      render :recovery_codes
    else
      redirect_to account_security_path, alert: "Check your current password and second-factor code."
    end
  end

  def two_factor
    if Current.user.disable_two_factor!(password: security_params[:password], code: security_params[:verification_code])
      start_new_session_for Current.user
      redirect_to account_security_path, notice: "Two-factor authentication disabled.", status: :see_other
    else
      redirect_to account_security_path, alert: "Check your current password and second-factor code.", status: :see_other
    end
  end

  private
    def security_params
      params.permit(:password, :verification_code)
    end

    def prevent_caching
      no_store
      # Native forms need a same-origin Origin header for Rails CSRF checks.
      response.set_header("Referrer-Policy", "same-origin")
    end

    def lock_account
      Current.user.with_lock do
        # A session revoked while this request waited for the lock cannot
        # change account security or mint a replacement authenticated session.
        if Session.exists?(id: Current.session.id, user_id: Current.user.id)
          yield
        else
          terminate_session
          redirect_to new_session_path
        end
      end
    end
end
