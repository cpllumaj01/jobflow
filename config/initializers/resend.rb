require Rails.root.join("lib/resend_delivery")

Resend.api_key = ENV["RESEND_API_KEY"]
ActionMailer::Base.add_delivery_method :resend, ResendDelivery
