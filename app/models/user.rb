class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :customers, dependent: :destroy
  has_many :jobs, through: :customers

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true
  validates :password, length: { minimum: 15 }, allow_nil: true

  after_update :revoke_sessions, if: :saved_change_to_password_digest?

  private
    def revoke_sessions
      sessions.destroy_all
    end
end
