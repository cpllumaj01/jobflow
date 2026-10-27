class AddTwoFactorAuthenticationToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :otp_secret, :text
    add_column :users, :otp_setup_secret, :text
    add_column :users, :otp_last_used_at, :bigint
    add_column :users, :recovery_code_digests, :jsonb, null: false, default: []
  end
end
