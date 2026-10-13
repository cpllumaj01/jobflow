class PasswordsMailer < ApplicationMailer
  def reset(user)
    @user = user
    mail subject: "Reset your JobFlow password", to: user.email_address
  end
end
