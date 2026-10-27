class User < ApplicationRecord
  has_secure_password
  encrypts :otp_secret, :otp_setup_secret
  has_many :sessions, dependent: :destroy
  has_many :customers, dependent: :destroy
  has_many :jobs, through: :customers
  has_many :activities, foreign_key: :actor_id, inverse_of: :actor, dependent: :nullify

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true
  validates :password, length: { minimum: 15 }, allow_nil: true

  after_update :revoke_sessions, if: :saved_change_to_password_digest?

  # Only a fingerprint is embedded in Rails' signed tokens. A password/security
  # change or a successful second factor invalidates outstanding challenges.
  generates_token_for :two_factor_login, expires_in: 5.minutes do
    two_factor_token_state
  end

  generates_token_for :two_factor_setup, expires_in: 10.minutes do
    Digest::SHA256.hexdigest([ two_factor_token_state, otp_setup_secret ].to_json)
  end

  def two_factor_enabled?
    otp_secret.present?
  end

  def two_factor_provisioning_uri(secret)
    ROTP::TOTP.new(secret, issuer: "JobFlow").provisioning_uri(email_address)
  end

  def enable_two_factor!(secret:, code:)
    with_lock do
      return false if two_factor_enabled?
      timestamp = verify_totp(secret, code)
      return false unless timestamp

      codes = new_recovery_codes
      update!(otp_secret: secret, otp_setup_secret: nil, otp_last_used_at: timestamp, recovery_code_digests: codes.map { |value| recovery_code_digest(value) })
      revoke_sessions
      codes
    end
  end

  def consume_two_factor!(code)
    with_lock do
      return false unless consume_two_factor(code)
      save!
      true
    end
  end

  def regenerate_recovery_codes!(password:, code:)
    with_lock do
      return false unless authenticate(password.to_s) && consume_two_factor(code)

      codes = new_recovery_codes
      update!(recovery_code_digests: codes.map { |value| recovery_code_digest(value) })
      revoke_sessions
      codes
    end
  end

  def disable_two_factor!(password:, code:)
    with_lock do
      return false unless authenticate(password.to_s) && consume_two_factor(code)

      update!(otp_secret: nil, otp_setup_secret: nil, otp_last_used_at: nil, recovery_code_digests: [])
      revoke_sessions
      true
    end
  end

  private
    def two_factor_token_state
      Digest::SHA256.hexdigest([ password_digest, otp_secret, otp_last_used_at, recovery_code_digests ].to_json)
    end

    def verify_totp(secret, code, after: nil)
      return unless code.to_s.match?(/\A[0-9]{6}\z/)

      # 30-second steps, with 15 seconds of tolerance in either direction for
      # clock skew and codes entered just across a boundary.
      ROTP::TOTP.new(secret).verify(code.to_s, drift_behind: 15, drift_ahead: 15, after: after)
    end

    def consume_two_factor(code)
      return false unless two_factor_enabled?

      if timestamp = verify_totp(otp_secret, code, after: otp_last_used_at)
        self.otp_last_used_at = timestamp
      else
        digest = recovery_code_digest(code)
        return false unless recovery_code_digests.any? { |value| ActiveSupport::SecurityUtils.secure_compare(value, digest) }

        self.recovery_code_digests = recovery_code_digests - [ digest ]
      end
      true
    end

    def new_recovery_codes
      Array.new(10) { SecureRandom.hex(16).scan(/.{4}/).join("-") }
    end

    def recovery_code_digest(code)
      Digest::SHA256.hexdigest(code.to_s.downcase.delete("- "))
    end

    def revoke_sessions
      sessions.destroy_all
    end
end
