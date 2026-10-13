require "resend/mailer"

# Use the official integration, keeping provider response bodies out of Rails logs.
class ResendDelivery < Resend::Mailer
  def deliver!(mail)
    mail[:options] = { idempotency_key: mail.message_id }
    super
  rescue Resend::Error => error
    raise error.class.new("Resend delivery failed; check the Resend dashboard"), cause: nil
  end
end
