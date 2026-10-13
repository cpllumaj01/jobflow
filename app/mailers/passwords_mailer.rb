class PasswordsMailer < ApplicationMailer
  def self.deliver_reset_later(user)
    return reset(user).deliver_later unless delivery_method == :resend

    token = user.password_reset_token
    expires_at = Time.current + user.password_reset_token_expires_in
    PasswordResetDeliveryJob.perform_later(token, reset(user, token: token).message.encoded, expires_at)
  end

  def reset(user, token: user.password_reset_token)
    @user = user
    @token = token
    mail subject: "Reset your JobFlow password", to: user.email_address
  end
end
