class PasswordResetDeliveryJob < ApplicationJob
  self.log_arguments = false

  retry_on Resend::Error::RateLimitExceededError, Resend::Error::InternalServerError,
    *ResendDelivery::NETWORK_ERRORS,
    wait: ->(attempt) { delay = 15 * 2**(attempt - 1); [ delay + rand * delay * 0.15, 120 ].min }, attempts: 4

  def self.encryptor
    key = Rails.application.key_generator.generate_key("jobflow/password-reset-delivery", ActiveSupport::MessageEncryptor.key_len("aes-256-gcm"))
    ActiveSupport::MessageEncryptor.new(key, cipher: "aes-256-gcm", serializer: JSON)
  end

  def self.encrypt_payload(token, encoded_email, expires_at)
    encryptor.encrypt_and_sign(
      { token: token, email: encoded_email, expires_at: expires_at.iso8601(6) },
      purpose: name, expires_at: expires_at
    )
  end

  def perform(encrypted_payload)
    return unless valid_payload_at?(Time.current)

    mail = Mail.new(payload.fetch("email"))
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

    return unless valid_payload_at?(Time.current + options[:wait])

    super
  end

  private
    def payload
      @payload ||= self.class.encryptor.decrypt_and_verify(arguments.first, purpose: self.class.name)
    rescue ActiveSupport::MessageEncryptor::InvalidMessage
      raise ActiveSupport::MessageEncryptor::InvalidMessage, "Unable to decrypt password reset email", cause: nil
    end

    def valid_payload_at?(time)
      payload && time < Time.iso8601(payload.fetch("expires_at")) - 1.minute && User.find_by_password_reset_token(payload.fetch("token"))
    end
end
