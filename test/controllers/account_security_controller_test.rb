require "test_helper"

class AccountSecurityControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as @user
  end

  test "settings require an authenticated session" do
    sign_out
    get account_security_path
    assert_redirected_to new_session_path
    post setup_account_security_path, params: { password: "password" }
    assert_redirected_to new_session_path
    patch enable_account_security_path, params: { verification_code: "123456" }
    assert_redirected_to new_session_path
    post recovery_codes_account_security_path, params: { password: "password", verification_code: "123456" }
    assert_redirected_to new_session_path
    delete two_factor_account_security_path, params: { password: "password", verification_code: "123456" }
    assert_redirected_to new_session_path
  end

  test "settings show status without revealing secrets" do
    get account_security_path
    assert_response :success
    assert_select "h1", "Account security"
    assert_select "a[href=?]", account_security_path, text: "Account security"
    assert_includes response.headers["Cache-Control"], "no-store"
    assert_select 'meta[name="turbo-cache-control"][content="no-cache"]'
    assert_equal "no-referrer", response.headers["Referrer-Policy"]
  end

  test "setup rejects incorrect and malformed passwords" do
    [ "wrong", nil, [ "password" ] ].each do |password|
      post setup_account_security_path, params: { password: password }
      assert_redirected_to account_security_path
      assert_nil request.session[:two_factor_setup]
      assert_not @user.reload.two_factor_enabled?
    end
  end

  test "setup remains disabled until confirmation and can be canceled or replaced" do
    post setup_account_security_path, params: { password: "password" }
    assert_response :success
    secret = @user.reload.otp_setup_secret
    assert secret.present?
    refute_includes request.session.to_hash.to_json, secret
    ciphertext = User.connection.select_value("SELECT otp_setup_secret FROM users WHERE id = #{@user.id}")
    refute_includes ciphertext, secret
    refute_includes @user.inspect, secret
    assert_includes response.body, secret
    assert_includes response.body, "otpauth://totp/JobFlow:"
    refute_includes cookies[rails_cookie_key], secret
    assert_not @user.reload.two_factor_enabled?
    assert_nil @user.otp_secret
    assert_includes response.headers["Cache-Control"], "no-store"

    get account_security_path
    refute_includes response.body, secret
    patch enable_account_security_path, params: { verification_code: "invalid" }
    assert_response :unprocessable_entity
    assert_not @user.reload.two_factor_enabled?

    old_setup_cookie = cookies[rails_cookie_key]
    post setup_account_security_path, params: { password: "password" }
    replacement_secret = @user.reload.otp_setup_secret
    assert_not_equal secret, replacement_secret
    replacement_cookie = cookies[rails_cookie_key]
    cookies[rails_cookie_key] = old_setup_cookie
    patch enable_account_security_path, params: { verification_code: ROTP::TOTP.new(secret).now }
    assert_redirected_to account_security_path
    assert_not @user.reload.two_factor_enabled?
    assert_equal replacement_secret, @user.otp_setup_secret
    cookies[rails_cookie_key] = replacement_cookie
    delete cancel_setup_account_security_path
    assert_redirected_to account_security_path
    assert_nil request.session[:two_factor_setup]
    assert_nil @user.reload.otp_setup_secret
    cookies[rails_cookie_key] = replacement_cookie
    patch enable_account_security_path, params: { verification_code: ROTP::TOTP.new(replacement_secret).now }
    assert_redirected_to account_security_path
    assert_not @user.reload.two_factor_enabled?
  end

  test "activation rotates the session revokes other sessions and shows codes only once" do
    other_browser = open_session
    other_browser.post session_path, params: { email_address: @user.email_address, password: "password" }
    get account_security_path
    previous_cookie = cookies[:session_id]
    other_user_session = users(:two).sessions.create!
    start_setup
    previous_id = request.session.id.public_id
    secret = @user.reload.otp_setup_secret
    patch enable_account_security_path, params: { verification_code: ROTP::TOTP.new(secret).now,
      user_id: users(:two).id, otp_secret: "untrusted", recovery_code_digests: [ "untrusted" ] }
    assert_response :success
    codes = css_select('ul[aria-label="Recovery codes"] li').map(&:text)
    assert_equal 10, codes.size
    assert @user.reload.two_factor_enabled?
    assert_equal secret, @user.otp_secret
    assert_nil @user.otp_setup_secret
    assert_equal 1, @user.sessions.count
    assert_not_equal previous_id, request.session.id.public_id
    assert_not_equal previous_cookie, cookies[:session_id]
    assert_nil request.session[:two_factor_setup]
    assert Session.exists?(other_user_session.id)
    assert_not users(:two).reload.two_factor_enabled?
    refute_includes response.body, secret
    assert_includes response.headers["Cache-Control"], "no-store"
    codes.each { |code| refute_includes request.session.to_hash.to_json, code }

    other_browser.get jobs_path
    other_browser.assert_redirected_to new_session_path
    get account_security_path
    codes.each { |code| refute_includes response.body, code }
    refute_includes response.body, secret
    assert_select "form[action=?]", two_factor_account_security_path do
      assert_select 'input[name="_method"][value="delete"]'
    end
  end

  test "setup expires and cannot be confirmed by another browser" do
    start_setup
    secret = @user.reload.otp_setup_secret
    other_browser = open_session
    other_browser.post session_path, params: { email_address: @user.email_address, password: "password" }
    other_browser.patch enable_account_security_path, params: { verification_code: ROTP::TOTP.new(secret).now }
    other_browser.assert_redirected_to account_security_path
    assert_not @user.reload.two_factor_enabled?
    travel 10.minutes + 1.second do
      patch enable_account_security_path, params: { verification_code: ROTP::TOTP.new(secret).now }
      assert_redirected_to account_security_path
      assert_nil request.session[:two_factor_setup]
      assert_not @user.reload.two_factor_enabled?
    end
  end

  test "revoked setup sessions and password changes prevent activation" do
    start_setup
    secret = @user.reload.otp_setup_secret
    @user.update!(password: "replacement-password")
    patch enable_account_security_path, params: { verification_code: ROTP::TOTP.new(secret).now }
    assert_redirected_to new_session_path
    assert_not @user.reload.two_factor_enabled?

    post session_path, params: { email_address: @user.email_address, password: "replacement-password" }
    patch enable_account_security_path, params: { verification_code: ROTP::TOTP.new(secret).now }
    assert_redirected_to account_security_path
    assert_not @user.reload.two_factor_enabled?
  end

  test "regeneration and disabling require both factors and preserve other accounts" do
    codes = activate
    previous_cookie = cookies[:session_id]
    [ { password: "wrong", verification_code: codes.first },
      { password: "password", verification_code: "invalid" },
      { password: "password" } ].each do |credentials|
      post recovery_codes_account_security_path, params: credentials
      assert_redirected_to account_security_path
      delete two_factor_account_security_path, params: credentials
      assert_redirected_to account_security_path
      assert @user.reload.two_factor_enabled?
      assert_equal 10, @user.recovery_code_digests.size
      assert_equal previous_cookie, cookies[:session_id]
    end

    other_secret = ROTP::Base32.random
    users(:two).enable_two_factor!(secret: other_secret, code: ROTP::TOTP.new(other_secret).now)
    other_state = users(:two).reload.attributes
    extra_session = @user.sessions.create!
    post recovery_codes_account_security_path, params: { password: "password", verification_code: codes.first, user_id: users(:two).id }
    assert_response :success
    replacement = css_select('ul[aria-label="Recovery codes"] li').map(&:text)
    assert_equal 10, replacement.size
    assert_not_equal previous_cookie, cookies[:session_id]
    assert_not Session.exists?(extra_session.id)
    codes.each { |code| assert_not @user.consume_two_factor!(code) }
    assert_equal other_state, users(:two).reload.attributes

    previous_cookie = cookies[:session_id]
    extra_session = @user.sessions.create!
    delete two_factor_account_security_path, params: { password: "password", verification_code: replacement.first, user_id: users(:two).id }
    assert_redirected_to account_security_path
    assert_not @user.reload.two_factor_enabled?
    assert_nil @user.otp_secret
    assert_empty @user.recovery_code_digests
    assert_not Session.exists?(extra_session.id)
    assert_not_equal previous_cookie, cookies[:session_id]
    assert_equal other_state, users(:two).reload.attributes
    get jobs_path
    assert_response :success
    delete session_path
    post session_path, params: { email_address: @user.email_address, password: "password" }
    assert_redirected_to root_path
  end

  test "management verification is rate limited across actions and IPs" do
    with_rate_limit_cache do
      10.times do |attempt|
        post setup_account_security_path, params: { password: "wrong" }, env: { "REMOTE_ADDR" => "192.0.2.#{attempt + 1}" }
        assert_response :redirect
      end
      delete two_factor_account_security_path, params: { password: "password", verification_code: "invalid" }, env: { "REMOTE_ADDR" => "192.0.2.20" }
      assert_response :too_many_requests
      travel 5.minutes + 1.second do
        post setup_account_security_path, params: { password: "password" }
        assert_response :success
      end
    end
  end

  test "management retains CSRF protection" do
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    post setup_account_security_path, params: { password: "password" }
    assert_response :unprocessable_entity
    assert_nil request.session[:two_factor_setup]
    assert_not @user.reload.two_factor_enabled?
  ensure
    ActionController::Base.allow_forgery_protection = previous
  end

  test "rendered management forms supply valid CSRF tokens for each action" do
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    get account_security_path
    post setup_account_security_path, params: { password: "password", authenticity_token: form_token(setup_account_security_path) }
    assert_response :success
    secret = @user.reload.otp_setup_secret
    patch enable_account_security_path, params: { verification_code: ROTP::TOTP.new(secret).now, authenticity_token: form_token(enable_account_security_path) }
    assert_response :success
    codes = css_select('ul[aria-label="Recovery codes"] li').map(&:text)

    get account_security_path
    post recovery_codes_account_security_path, params: { password: "password", verification_code: codes.first,
      authenticity_token: form_token(recovery_codes_account_security_path) }
    assert_response :success
    replacement = css_select('ul[aria-label="Recovery codes"] li').map(&:text)
    get account_security_path
    delete two_factor_account_security_path, params: { password: "password", verification_code: replacement.first,
      authenticity_token: form_token(two_factor_account_security_path) }
    assert_redirected_to account_security_path
    assert_not @user.reload.two_factor_enabled?
  ensure
    ActionController::Base.allow_forgery_protection = previous
  end

  test "setup and recovery credentials do not appear in application logs" do
    output = StringIO.new
    logger = ActiveSupport::Logger.new(output)
    logger.level = Logger::DEBUG
    Rails.logger.broadcast_to(logger)
    start_setup
    secret = @user.reload.otp_setup_secret
    verification_code = ROTP::TOTP.new(secret).now
    patch enable_account_security_path, params: { verification_code: verification_code }
    assert_response :success
    codes = css_select('ul[aria-label="Recovery codes"] li').map(&:text)
    get account_security_path
    post recovery_codes_account_security_path, params: { password: "password", verification_code: codes.first }
    assert_response :success
    replacement = css_select('ul[aria-label="Recovery codes"] li').map(&:text)

    assert_includes output.string, "[FILTERED]"
    [ secret, verification_code, *codes, *replacement ].each { |credential| refute_includes output.string, credential }
  ensure
    Rails.logger.stop_broadcasting_to(logger) if logger
  end

  private
    def form_token(path)
      css_select("form[action='#{path}'] input[name='authenticity_token']").first["value"]
    end

    def start_setup
      post setup_account_security_path, params: { password: "password" }
      assert_response :success
    end

    def activate
      start_setup
      secret = @user.reload.otp_setup_secret
      patch enable_account_security_path, params: { verification_code: ROTP::TOTP.new(secret).now }
      assert_response :success
      css_select('ul[aria-label="Recovery codes"] li').map(&:text)
    end

    def rails_cookie_key
      Rails.application.config.session_options[:key]
    end

    def with_rate_limit_cache
      cache = AccountSecurityController.cache_store
      original = cache.method(:increment)
      store = ActiveSupport::Cache::MemoryStore.new
      cache.define_singleton_method(:increment) { |*args, **options| store.increment(*args, **options) }
      yield
    ensure
      cache.define_singleton_method(:increment, original)
    end
end
