class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[ new create ]
  rate_limit to: 10, within: 3.minutes, name: "ip", only: :create, with: -> { redirect_to new_session_path, alert: "Try again later." }
  rate_limit to: 10, within: 15.minutes, name: "email", only: :create,
    by: -> { Digest::SHA256.hexdigest(params.permit(:email_address)[:email_address].to_s.strip.downcase) },
    with: -> { redirect_to new_session_path, alert: "Try again later." }

  def new
  end

  def create
    credentials = params.permit(:email_address, :password)

    if user = User.authenticate_by(email_address: credentials[:email_address], password: credentials[:password])
      return_to = after_authentication_url
      start_new_session_for user
      redirect_to return_to
    else
      redirect_to new_session_path, alert: "Try another email address or password."
    end
  end

  def destroy
    terminate_session
    redirect_to new_session_path, status: :see_other
  end
end
