class PasswordResetDeliveryJob < ApplicationJob
  self.log_arguments = false

  retry_on Resend::Error::RateLimitExceededError, Resend::Error::InternalServerError,
    *ResendDelivery::NETWORK_ERRORS,
    wait: ->(attempt) { delay = 15 * 2**(attempt - 1); [ delay + rand * delay * 0.15, 120 ].min }, attempts: 4

  def perform(token, encoded_email, expires_at)
    return unless Time.current < expires_at - 1.minute && User.find_by_password_reset_token(token)

    mail = Mail.new(encoded_email)
    mail.delivery_method(ResendDelivery)
    mail.raise_delivery_errors = true
    mail.deliver!
  end

  def retry_job(options = {})
    error = options[:error]
    if error.is_a?(Resend::Error::RateLimitExceededError) && error.retry_after
      raise error if error.retry_after > 120
      options[:wait] = [ options[:wait], error.retry_after ].max
    end

    token, _encoded_email, expires_at = arguments
    return unless Time.current + options[:wait] < expires_at - 1.minute && User.find_by_password_reset_token(token)

    super
  end
end
