require "test_helper"

class AuthenticationThrottlingTest < ActionDispatch::IntegrationTest
  setup { @user = users(:one) }

  test "unavailable IP or email counters prevent password-only login" do
    [ 1, 2 ].each do |failed_counter|
      with_unavailable_counter(failed_counter) do
        assert_no_difference "Session.count" do
          password_login
        end
        assert_response :too_many_requests
        assert cookies[:session_id].blank?
      end
    end
    password_login
    assert_redirected_to root_path
  end

  test "unavailable counters prevent starting a second-factor challenge" do
    enable_two_factor
    [ 1, 2 ].each do |failed_counter|
      with_unavailable_counter(failed_counter) do
        password_login
        assert_response :too_many_requests
        assert_nil request.session[:two_factor_login_token]
        assert_empty @user.sessions
      end
    end
  end

  test "unavailable counters prevent TOTP consumption and authentication" do
    enable_two_factor
    password_login
    previous_step = @user.reload.otp_last_used_at
    travel 30.seconds do
      [ 1, 2 ].each do |failed_counter|
        with_unavailable_counter(failed_counter) do
          post two_factor_challenge_path, params: { verification_code: @totp.now }
          assert_response :too_many_requests
          assert_empty @user.sessions
          assert_equal previous_step, @user.reload.otp_last_used_at
          assert request.session[:two_factor_login_token]
        end
      end
      post two_factor_challenge_path, params: { verification_code: @totp.now }
      assert_redirected_to root_path
    end
  end

  test "unavailable counters prevent recovery-code consumption and recover normally" do
    codes = enable_two_factor
    password_login
    [ 1, 2 ].each do |failed_counter|
      with_unavailable_counter(failed_counter) do
        post two_factor_challenge_path, params: { verification_code: codes.first }
        assert_response :too_many_requests
        assert_empty @user.sessions
        assert_equal 10, @user.reload.recovery_code_digests.size
      end
    end
    post two_factor_challenge_path, params: { verification_code: codes.first }
    assert_redirected_to root_path
    assert_equal 9, @user.reload.recovery_code_digests.size
  end

  test "unavailable counters prevent setup and activation" do
    sign_in_as @user
    [ 1, 2 ].each do |failed_counter|
      with_unavailable_counter(failed_counter) do
        post setup_account_security_path, params: { password: "password" }
        assert_response :too_many_requests
        assert_nil @user.reload.otp_setup_secret
        assert_nil request.session[:two_factor_setup]
      end
    end
    post setup_account_security_path, params: { password: "password" }
    assert_response :success
    code = ROTP::TOTP.new(@user.reload.otp_setup_secret).now
    [ 1, 2 ].each do |failed_counter|
      with_unavailable_counter(failed_counter) do
        patch enable_account_security_path, params: { verification_code: code }
        assert_response :too_many_requests
        assert_not @user.reload.two_factor_enabled?
        assert_empty @user.recovery_code_digests
      end
    end
    patch enable_account_security_path, params: { verification_code: code }
    assert_response :success
    assert @user.reload.two_factor_enabled?
  end

  test "unavailable counters prevent regeneration disabling and session revocation" do
    codes = enable_two_factor
    sign_in_as @user
    existing_session_ids = @user.sessions.ids
    [ 1, 2 ].each do |failed_counter|
      [ :regenerate, :disable ].each do |operation|
        with_unavailable_counter(failed_counter) do
          credentials = { password: "password", verification_code: codes.first }
          if operation == :regenerate
            post recovery_codes_account_security_path, params: credentials
          else
            delete two_factor_account_security_path, params: credentials
          end
          assert_response :too_many_requests
          assert @user.reload.two_factor_enabled?
          assert_equal 10, @user.recovery_code_digests.size
          assert_equal existing_session_ids, @user.sessions.ids
        end
      end
    end
    delete two_factor_account_security_path, params: { password: "password", verification_code: codes.first }
    assert_redirected_to account_security_path
    assert_not @user.reload.two_factor_enabled?
  end

  test "unavailable counters prevent password reset delivery" do
    with_unavailable_counter(1) do
      assert_no_enqueued_jobs only: PasswordResetDeliveryJob do
        post passwords_path, params: { email_address: @user.email_address }
      end
      assert_response :too_many_requests
    end
    assert_enqueued_jobs 1, only: PasswordResetDeliveryJob do
      post passwords_path, params: { email_address: @user.email_address }
    end
    assert_response :redirect
  end

  private
    def enable_two_factor
      @totp = ROTP::TOTP.new(ROTP::Base32.random)
      @user.enable_two_factor!(secret: @totp.secret, code: @totp.now)
    end

    def password_login
      post session_path, params: { email_address: @user.email_address, password: "password" }
    end

    def with_unavailable_counter(failed_counter)
      cache = ActionController::Base.cache_store
      original = cache.method(:increment)
      calls = 0
      cache.define_singleton_method(:increment) do |*args, **options|
        calls += 1
        calls == failed_counter ? nil : original.call(*args, **options)
      end
      yield
      assert_equal failed_counter, calls
    ensure
      cache.define_singleton_method(:increment, original)
    end
end
