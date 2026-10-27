require "test_helper"

class UserTwoFactorTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @secret = ROTP::Base32.random
    @totp = ROTP::TOTP.new(@secret)
  end

  test "enabling requires valid TOTP and revokes existing sessions" do
    own_session = @user.sessions.create!
    other_session = users(:two).sessions.create!
    assert_not @user.enable_two_factor!(secret: @secret, code: "invalid")
    assert_not @user.reload.two_factor_enabled?
    assert Session.exists?(own_session.id)

    codes = enable_two_factor
    assert @user.reload.two_factor_enabled?
    assert_not Session.exists?(own_session.id)
    assert Session.exists?(other_session.id)
    assert_equal 10, codes.uniq.size
    assert codes.all? { |code| code.match?(/\A(?:[0-9a-f]{4}-){7}[0-9a-f]{4}\z/) }
    assert_equal 10, @user.recovery_code_digests.size
    codes.each { |code| refute_includes @user.recovery_code_digests.to_json, code }
    ciphertext = User.connection.select_value("SELECT otp_secret FROM users WHERE id = #{@user.id}")
    refute_includes ciphertext, @secret
    assert_equal @secret, @user.reload.otp_secret
    refute_includes @user.inspect, @secret
    assert_includes @user.two_factor_provisioning_uri(@secret), "otpauth://totp/JobFlow:"
  end

  test "TOTP rejects invalid expired future and reused codes but permits small skew" do
    enable_two_factor
    assert_not @user.consume_two_factor!(@totp.now)
    assert_not @user.consume_two_factor!("1234567")
    assert_not @user.consume_two_factor!("123456junk")
    assert_not @user.consume_two_factor!(@totp.at(2.minutes.ago))
    assert_not @user.consume_two_factor!(@totp.at(2.minutes.from_now))
    travel_to Time.at((Time.current.to_i / 30 + 2) * 30 + 5) do
      assert @user.consume_two_factor!(@totp.at(10.seconds.ago))
      assert_not @user.consume_two_factor!(@totp.at(10.seconds.ago))
    end
  end

  test "recovery codes are single use and tolerate capitalization and formatting" do
    codes = enable_two_factor
    assert @user.consume_two_factor!(codes.first.upcase.delete("-"))
    assert_not @user.reload.consume_two_factor!(codes.first)
    assert_equal 9, @user.recovery_code_digests.size
    assert @user.consume_two_factor!(codes.last)
  end

  test "regeneration requires both factors invalidates all old codes and revokes sessions" do
    codes = enable_two_factor
    session = @user.sessions.create!
    assert_not @user.regenerate_recovery_codes!(password: "wrong", code: codes.first)
    assert_not @user.regenerate_recovery_codes!(password: "password", code: "invalid")
    assert_equal 10, @user.reload.recovery_code_digests.size
    assert Session.exists?(session.id)

    replacement = @user.regenerate_recovery_codes!(password: "password", code: codes.first)
    assert_equal 10, replacement.size
    assert_not Session.exists?(session.id)
    codes.each { |code| assert_not @user.consume_two_factor!(code) }
    assert @user.consume_two_factor!(replacement.first)
  end

  test "disable requires both factors and clears credentials and sessions" do
    codes = enable_two_factor
    session = @user.sessions.create!
    assert_not @user.disable_two_factor!(password: "wrong", code: codes.first)
    assert_not @user.disable_two_factor!(password: "password", code: "invalid")
    assert @user.reload.two_factor_enabled?
    assert Session.exists?(session.id)
    assert @user.disable_two_factor!(password: "password", code: codes.first)
    assert_not @user.reload.two_factor_enabled?
    assert_nil @user.otp_last_used_at
    assert_empty @user.recovery_code_digests
    assert_empty @user.sessions
    assert_not @user.consume_two_factor!(codes.last)
  end

  test "login tokens expire and become invalid after a successful factor or password change" do
    codes = enable_two_factor
    token = @user.generate_token_for(:two_factor_login)
    assert_equal @user, User.find_by_token_for(:two_factor_login, token)
    travel 5.minutes + 1.second do
      assert_nil User.find_by_token_for(:two_factor_login, token)
    end
    assert @user.consume_two_factor!(codes.first)
    assert_nil User.find_by_token_for(:two_factor_login, token)
    token = @user.generate_token_for(:two_factor_login)
    @user.update!(password: "replacement-password")
    assert_nil User.find_by_token_for(:two_factor_login, token)
    assert @user.reload.two_factor_enabled?
  end

  private
    def enable_two_factor
      @user.enable_two_factor!(secret: @secret, code: @totp.now)
    end
end
