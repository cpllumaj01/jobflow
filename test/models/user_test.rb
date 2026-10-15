require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "downcases and strips email_address" do
    user = User.new(email_address: " DOWNCASED@EXAMPLE.COM ")
    assert_equal("downcased@example.com", user.email_address)
  end

  test "new passwords must contain at least fifteen characters" do
    user = User.new(email_address: "new@example.com", password: "a" * 14)

    assert_not user.valid?
    assert user.errors.added?(:password, :too_short, count: 15)

    user.password = "a" * 15
    assert user.valid?
  end

  test "long passwords remain valid up to bcrypt's seventy two byte limit" do
    [ "a" * 64, "a" * 72, "é" * 36 ].each do |password|
      user = User.new(email_address: "new@example.com", password: password)
      assert user.valid?, user.errors.full_messages.join(", ")
    end

    [ "a" * 73, "é" * 37 ].each do |password|
      user = User.new(email_address: "new@example.com", password: password)
      assert_not user.valid?
      assert user.errors[:password].any?
    end
  end

  test "minimum password length counts characters rather than bytes" do
    user = User.new(email_address: "new@example.com", password: "é" * 14)
    assert_not user.valid?

    user.password = "é" * 15
    assert user.valid?
  end

  test "passwords may contain spaces and need no character mixtures" do
    [ "lowercase words only", "  spaced words  ", "a" * 15 ].each do |password|
      user = User.new(email_address: "new@example.com", password: password)
      assert user.valid?, user.errors.full_messages.join(", ")
    end
  end

  test "new accounts still require a password and matching confirmation" do
    user = User.new(email_address: "new@example.com")
    assert_not user.valid?
    assert user.errors.added?(:password, :blank)

    user.password = "replacement-password"
    user.password_confirmation = "different-password"
    assert_not user.valid?
    assert user.errors[:password_confirmation].any?

    user.password_confirmation = user.password
    assert user.valid?
  end

  test "existing short passwords still authenticate and permit unrelated updates" do
    user = users(:one)
    digest = user.password_digest

    assert user.authenticate("password")
    assert user.update(email_address: "updated@example.com")
    assert_equal digest, user.reload.password_digest
    assert user.authenticate("password")
  end

  test "changing a password revokes all of that user's sessions" do
    user = users(:one)
    user.sessions.create!
    user.sessions.create!
    other_session = users(:two).sessions.create!

    user.update!(password: "replacement-password")

    assert_empty user.sessions.reload
    assert Session.exists?(other_session.id)
    assert user.reload.authenticate("replacement-password")
    assert_not user.authenticate("password")
  end

  test "failed password changes and unrelated updates preserve existing sessions" do
    user = users(:one)
    session = user.sessions.create!
    digest = user.password_digest

    assert_not user.update(password: "short")
    assert_equal digest, user.reload.password_digest
    assert Session.exists?(session.id)

    user = User.find(user.id)
    user.update!(email_address: "updated@example.com")
    assert Session.exists?(session.id)
  end

  test "changing a password invalidates all outstanding reset tokens" do
    user = users(:one)
    first_token = user.password_reset_token
    second_token = travel(1.second) { user.password_reset_token }

    user.update!(password: "replacement-password")

    assert_nil User.find_by_password_reset_token(first_token)
    assert_nil User.find_by_password_reset_token(second_token)
    assert_equal user, User.find_by_password_reset_token(user.password_reset_token)
  end
end
