class AddTwoFactorChallengeVersionToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :two_factor_challenge_version, :bigint, null: false, default: 0
  end
end
