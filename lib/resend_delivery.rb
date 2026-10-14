require "resend/mailer"

# Use the official integration, keeping provider response bodies out of Rails logs.
class ResendDelivery < Resend::Mailer
  NETWORK_ERRORS = [ Timeout::Error, SocketError, EOFError, Errno::ECONNRESET,
    Errno::ECONNREFUSED, Errno::ECONNABORTED, Errno::ETIMEDOUT,
    Errno::EHOSTUNREACH, Errno::ENETUNREACH, Errno::EPIPE ].freeze

  # SDK 1.17 does not expose HTTP status on exceptions and maps most 5xx to
  # the generic Error. Use its public error handler to classify only 5xx.
  class Request < Resend::Request
    def handle_error!(data, response = nil)
      if (500..599).cover?(data[:statusCode])
        raise Resend::Error::InternalServerError.new("Resend server error")
      end
      super
    end
  end

  def deliver!(mail)
    response = Request.new("emails", build_resend_params(mail), "post", options: { idempotency_key: mail.message_id }).perform
    mail.message_id = response[:id]
  rescue Resend::Error => error
    message = "Resend delivery failed (#{error.class.name})"

    headers = {}
    if error.is_a?(Resend::Error::RateLimitExceededError) && error.retry_after.is_a?(Numeric)
      message += "; retry after #{error.retry_after}s"
      headers["retry-after"] = error.retry_after.to_s
    end
    raise error.class.new(message, nil, headers), cause: nil
  rescue *NETWORK_ERRORS => error
    raise error.class, "Resend delivery failed (#{error.class.name})", cause: nil
  end
end
