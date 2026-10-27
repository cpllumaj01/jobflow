require "test_helper"

class TwoFactorChallengesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @secret = ROTP::Base32.random
    @totp = ROTP::TOTP.new(@secret)
    @codes = @user.enable_two_factor!(secret: @secret, code: @totp.now)
  end

  test "a password check creates only a limited challenge and rotates preauthentication state" do
    get job_path(jobs(:kitchen_renovation))
    previous_id = request.session.id.public_id
    assert_no_difference "Session.count" do
      password_login
    end
    assert_redirected_to new_two_factor_challenge_path
    assert_not_equal previous_id, request.session.id.public_id
    assert cookies[:session_id].blank?
    assert_nil Current.session
    assert request.session[:two_factor_login_token]
    refute_includes request.session.to_hash.to_json, @secret
    get new_two_factor_challenge_path
    assert_response :success
    assert_select 'nav[aria-label="Main navigation"]', count: 0
    assert_select 'meta[name="turbo-cache-control"][content="no-cache"]'
    assert_includes response.headers["Cache-Control"], "no-store"
    refute_includes response.body, @secret
    @codes.each { |code| refute_includes response.body, code }
  end

  test "pending authentication cannot access business resources or account security" do
    password_login
    [ root_path, jobs_path, customers_path, job_path(jobs(:kitchen_renovation)),
      job_estimate_path(jobs(:kitchen_renovation)), job_change_orders_path(jobs(:kitchen_renovation)),
      api_v1_jobs_path, account_security_path ].each do |path|
      get path
      assert_redirected_to new_session_path
      assert_nil Current.session
    end
    assert_empty @user.sessions
  end

  test "TOTP verification establishes and rotates the session and preserves the intended destination" do
    get job_path(jobs(:kitchen_renovation))
    password_login
    previous_id = request.session.id.public_id
    # Access attempts during the challenge must not replace the original destination.
    get customers_path
    travel 30.seconds do
      assert_difference "@user.sessions.count", 1 do
        post two_factor_challenge_path, params: { verification_code: @totp.now, user_id: users(:two).id }
      end
    end
    assert_redirected_to job_path(jobs(:kitchen_renovation))
    assert_equal @user.id, Session.find_by!(user_id: @user.id).user_id
    assert cookies[:session_id]
    assert_not_equal previous_id, request.session.id.public_id
    assert_nil request.session[:two_factor_login_token]
    assert_nil request.session[:return_to_after_authenticating]
    get api_v1_jobs_path
    assert_response :success
    delete session_path
    assert_redirected_to new_session_path
    assert_empty @user.sessions
  end

  test "invalid passwords do not reveal two factor status or leave an old challenge" do
    password_login
    post session_path, params: { email_address: @user.email_address, password: "wrong" }
    assert_redirected_to new_session_path
    assert_equal "Try another email address or password.", flash[:alert]
    assert_nil request.session[:two_factor_login_token]
    assert cookies[:session_id].blank?
    post two_factor_challenge_path, params: { verification_code: @codes.first }
    assert_redirected_to new_session_path
    assert_empty @user.sessions
  end

  test "invalid expired reused and malformed TOTP do not authenticate" do
    password_login
    [ "invalid", @totp.now, @totp.at(2.minutes.ago), @totp.at(2.minutes.from_now),
      nil, [ @totp.now ], { value: @totp.now } ].each do |code|
      assert_no_difference "Session.count" do
        post two_factor_challenge_path, params: { verification_code: code, user_id: users(:two).id }
      end
      assert_response :unprocessable_entity
      assert cookies[:session_id].blank?
      assert_nil Current.session
      assert request.session[:two_factor_login_token]
    end
  end

  test "verification requires an unexpired pending challenge from this browser" do
    [ :get, :post ].each do |verb|
      public_send(verb, verb == :get ? new_two_factor_challenge_path : two_factor_challenge_path,
        params: { verification_code: @codes.first, user_id: @user.id })
      assert_redirected_to new_session_path
    end
    password_login
    other_browser = open_session
    other_browser.post two_factor_challenge_path, params: { verification_code: @codes.first, user_id: @user.id }
    other_browser.assert_redirected_to new_session_path
    travel 5.minutes + 1.second do
      post two_factor_challenge_path, params: { verification_code: @codes.first }
      assert_redirected_to new_session_path
      assert_nil request.session[:two_factor_login_token]
      assert_empty @user.sessions
    end
  end

  test "a recovery code signs in once and a completed challenge cookie cannot be replayed" do
    password_login
    previous_cookie = cookies[rails_cookie_key]
    post two_factor_challenge_path, params: { verification_code: @codes.first }
    assert_redirected_to root_path
    assert_equal 9, @user.reload.recovery_code_digests.size
    assert_equal 1, @user.sessions.count
    delete session_path
    cookies[rails_cookie_key] = previous_cookie
    post two_factor_challenge_path, params: { verification_code: @codes.last }
    assert_redirected_to new_session_path
    assert_empty @user.sessions
    assert_equal 9, @user.reload.recovery_code_digests.size

    password_login
    post two_factor_challenge_path, params: { verification_code: @codes.first }
    assert_response :unprocessable_entity
    assert_empty @user.sessions
  end

  test "a completed TOTP challenge cannot be replayed with a new code" do
    password_login
    previous_cookie = cookies[rails_cookie_key]
    travel 30.seconds do
      post two_factor_challenge_path, params: { verification_code: @totp.now }
      assert_redirected_to root_path
    end
    delete session_path
    cookies[rails_cookie_key] = previous_cookie
    travel 60.seconds do
      post two_factor_challenge_path, params: { verification_code: @totp.now }
      assert_redirected_to new_session_path
      assert_empty @user.sessions
    end
  end

  test "cancel clears pending state and rotates the browser session" do
    password_login
    previous_id = request.session.id.public_id
    delete two_factor_challenge_path
    assert_redirected_to new_session_path
    assert_not_equal previous_id, request.session.id.public_id
    assert_nil request.session[:two_factor_login_token]
    post two_factor_challenge_path, params: { verification_code: @codes.first }
    assert_redirected_to new_session_path
    assert_empty @user.sessions
  end

  test "cancel rejects a restored challenge cookie and fresh sign in still works" do
    password_login
    key = rails_cookie_key
    saved_cookie = cookies[key]
    other_user_version = users(:two).two_factor_challenge_version

    delete two_factor_challenge_path, params: { user_id: users(:two).id }
    assert_redirected_to new_session_path
    assert_equal 1, @user.reload.two_factor_challenge_version
    assert_equal other_user_version, users(:two).reload.two_factor_challenge_version

    cookies[key] = saved_cookie
    assert_no_difference "Session.count" do
      post two_factor_challenge_path, params: { verification_code: @codes.first }
    end
    assert_redirected_to new_session_path
    assert_equal 10, @user.reload.recovery_code_digests.size

    password_login
    new_cookie = cookies[key]
    cookies[key] = saved_cookie
    assert_no_changes -> { @user.reload.two_factor_challenge_version } do
      delete two_factor_challenge_path
    end
    cookies[key] = new_cookie
    post two_factor_challenge_path, params: { verification_code: @codes.first }
    assert_redirected_to root_path
    assert_equal 1, @user.sessions.count
  end

  test "canceling missing expired or completed challenges cannot invalidate current authentication" do
    assert_no_changes -> { @user.reload.two_factor_challenge_version } do
      delete two_factor_challenge_path, params: { user_id: @user.id }
    end

    password_login
    travel 5.minutes + 1.second do
      assert_no_changes -> { @user.reload.two_factor_challenge_version } do
        delete two_factor_challenge_path
      end
    end

    password_login
    saved_cookie = cookies[rails_cookie_key]
    post two_factor_challenge_path, params: { verification_code: @codes.first }
    authentication_cookie = cookies[:session_id]
    cookies[rails_cookie_key] = saved_cookie
    assert_no_changes -> { @user.reload.two_factor_challenge_version } do
      delete two_factor_challenge_path
    end
    assert_equal authentication_cookie, cookies[:session_id]
    get jobs_path
    assert_response :success
    assert_equal 1, @user.sessions.count
  end

  test "starting a challenge drops a previously authenticated session" do
    sign_in_as users(:two)
    previous = Current.session
    old_cookie = cookies[:session_id]
    password_login
    assert_not Session.exists?(previous.id)
    assert cookies[:session_id].blank?
    cookies[:session_id] = old_cookie
    get jobs_path
    assert_redirected_to new_session_path
  end

  test "password resets invalidate pending challenges and keep two factor enabled" do
    password_login
    token = @user.password_reset_token
    put password_path(token), params: { password: "replacement-password", password_confirmation: "replacement-password" }
    assert_redirected_to new_session_path
    assert @user.reload.two_factor_enabled?
    post two_factor_challenge_path, params: { verification_code: @codes.first }
    assert_redirected_to new_session_path
    assert_empty @user.sessions
    post session_path, params: { email_address: @user.email_address, password: "replacement-password" }
    assert_redirected_to new_two_factor_challenge_path
    post two_factor_challenge_path, params: { verification_code: @codes.first }
    assert_redirected_to root_path
    assert_equal 1, @user.sessions.count
  end

  test "disabled or regenerated security settings invalidate outstanding challenges" do
    password_login
    @user.regenerate_recovery_codes!(password: "password", code: @codes.first)
    post two_factor_challenge_path, params: { verification_code: @codes.last }
    assert_redirected_to new_session_path
    password_login
    travel 30.seconds do
      @user.disable_two_factor!(password: "password", code: @totp.now)
      post two_factor_challenge_path, params: { verification_code: @totp.now }
      assert_redirected_to new_session_path
      assert_empty @user.sessions
    end
  end

  test "return destinations cannot redirect outside the application" do
    key = rails_cookie_key
    jar = ActionDispatch::TestRequest.create.cookie_jar
    jar.encrypted[key] = { session_id: SecureRandom.hex(16), return_to_after_authenticating: "https://attacker.example/jobs" }
    cookies[key] = jar[key]
    password_login
    post two_factor_challenge_path, params: { verification_code: @codes.first }
    assert_redirected_to root_path
  end

  test "second factor verification is rate limited by account across IPs" do
    with_rate_limit_cache do
      password_login
      10.times do |attempt|
        post two_factor_challenge_path, params: { verification_code: "invalid" }, env: { "REMOTE_ADDR" => "192.0.2.#{attempt + 1}" }
        assert_response :unprocessable_entity
      end
      post two_factor_challenge_path, params: { verification_code: @codes.first }, env: { "REMOTE_ADDR" => "192.0.2.20" }
      assert_response :too_many_requests
      assert_empty @user.sessions
      travel 5.minutes + 1.second do
        password_login
        post two_factor_challenge_path, params: { verification_code: @codes.first }
        assert_redirected_to root_path
      end
    end
  end

  test "second factor verification is rate limited by IP across accounts" do
    second_user = users(:two)
    secret = ROTP::Base32.random
    other_codes = second_user.enable_two_factor!(secret: secret, code: ROTP::TOTP.new(secret).now)
    with_rate_limit_cache do
      password_login
      other_browser = open_session
      other_browser.post session_path, params: { email_address: second_user.email_address, password: "password" }
      5.times do
        post two_factor_challenge_path, params: { verification_code: "invalid" }
        other_browser.post two_factor_challenge_path, params: { verification_code: "invalid" }
      end
      other_browser.post two_factor_challenge_path, params: { verification_code: other_codes.first }
      other_browser.assert_response :too_many_requests
      assert_empty second_user.sessions
    end
  end

  private
    def password_login
      post session_path, params: { email_address: @user.email_address, password: "password" }
    end

    def rails_cookie_key
      Rails.application.config.session_options[:key]
    end

    def with_rate_limit_cache
      cache = TwoFactorChallengesController.cache_store
      original = cache.method(:increment)
      store = ActiveSupport::Cache::MemoryStore.new
      cache.define_singleton_method(:increment) { |*args, **options| store.increment(*args, **options) }
      yield
    ensure
      cache.define_singleton_method(:increment, original)
    end
end
