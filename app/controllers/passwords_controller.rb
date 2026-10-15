class PasswordsController < ApplicationController
  allow_unauthenticated_access
  before_action :set_user_by_token, only: %i[ edit update ]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_password_path, alert: "Try again later." }

  def new
  end

  def create
    if user = User.find_by(email_address: params.permit(:email_address)[:email_address])
      PasswordsMailer.deliver_reset_later(user)
    end

    redirect_to new_session_path, notice: "Password reset instructions sent (if user with that email address exists)."
  end

  def edit
  end

  def update
    current_session = resume_session
    password_params = params.permit(:password, :password_confirmation)

    @user.with_lock do
      # Recheck after locking so concurrent requests cannot reuse a consumed token.
      User.find_by_password_reset_token!(params[:token])

      if password_params[:password].to_s.empty?
        redirect_to edit_password_path(params[:token]), alert: "Password can't be blank."
      elsif @user.update(password_params)
        terminate_session if current_session&.user_id == @user.id
        redirect_to new_session_path, notice: "Password has been reset."
      else
        redirect_to edit_password_path(params[:token]), alert: @user.errors.full_messages.to_sentence
      end
    end
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    redirect_to new_password_path, alert: "Password reset link is invalid or has expired."
  end

  private
    def set_user_by_token
      @user = User.find_by_password_reset_token!(params[:token])
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      redirect_to new_password_path, alert: "Password reset link is invalid or has expired."
    end
end
