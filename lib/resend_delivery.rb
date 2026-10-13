require "resend/mailer"

# Use the official integration, keeping provider response bodies out of Rails logs.
class ResendDelivery < Resend::Mailer
  def deliver!(mail)
    mail[:options] = { idempotency_key: mail.message_id }
    super
  rescue Resend::Error => error
    message = "Resend delivery failed (#{error.class.name})"

    if error.is_a?(Resend::Error::RateLimitExceededError) && error.retry_after.is_a?(Numeric)
      message += "; retry after #{error.retry_after}s"
    end

    raise error.class.new(message), cause: nil
  end
end
