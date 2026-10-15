require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  setup { @user = users(:one) }

  test "new" do
    get new_session_path
    assert_response :success
    assert_select 'link[rel="icon"]', count: 1 do
      assert_select '[href="/jobflow-icon.svg"][type="image/svg+xml"][sizes="any"]'
    end
    assert_select 'link[rel="apple-touch-icon"][href="/jobflow-icon.png"]'
  end

  test "create with valid credentials" do
    assert_difference "@user.sessions.count", 1 do
      post session_path, params: { email_address: " ONE@EXAMPLE.COM ", password: "password" }
    end

    assert_redirected_to root_path
    assert cookies[:session_id]

    get jobs_path
    assert_response :success
  end

  test "create with invalid credentials" do
    post session_path, params: { email_address: @user.email_address, password: "wrong" }

    assert_redirected_to new_session_path
    assert_nil cookies[:session_id]
  end

  test "unknown accounts and invalid or missing credentials receive the same failure" do
    [ { email_address: @user.email_address, password: "wrong" },
      { email_address: "missing@example.com", password: "wrong" },
      { email_address: @user.email_address },
      { password: "password" },
      { email_address: @user.email_address, password: "" },
      { email_address: [ @user.email_address ], password: "password" },
      { email_address: @user.email_address, password: [ "password" ] },
      { email_address: @user.email_address, password: { value: "password" } } ].each do |credentials|
      assert_no_difference "Session.count" do
        post session_path, params: credentials
      end

      assert_response :redirect
      assert_redirected_to new_session_path
      assert_equal "Try another email address or password.", flash[:alert]
      assert_nil cookies[:session_id]
    end
  end

  test "login rate limit restricts an IP across different accounts and expires" do
    with_rate_limit_cache do
      10.times do |attempt|
        post session_path, params: { email_address: "missing#{attempt}@example.com", password: "wrong" }
        assert_equal "Try another email address or password.", flash[:alert]
      end

      assert_no_difference "Session.count" do
        post session_path, params: { email_address: @user.email_address, password: "password" }
      end
      assert_redirected_to new_session_path
      assert_equal "Try again later.", flash[:alert]

      travel 3.minutes + 1.second do
        post session_path, params: { email_address: @user.email_address, password: "password" }
        assert_redirected_to root_path
      end
    end
  end

  test "login rate limit follows normalized emails across IPs for known and unknown accounts" do
    [ @user.email_address, "missing@example.com" ].each do |email|
      with_rate_limit_cache do
        10.times do |attempt|
          post session_path, params: { email_address: " #{email.upcase} ", password: "wrong" },
            env: { "REMOTE_ADDR" => "192.0.2.#{attempt + 1}" }
          assert_equal "Try another email address or password.", flash[:alert]
        end

        assert_no_difference "Session.count" do
          post session_path, params: { email_address: email, password: "password" },
            env: { "REMOTE_ADDR" => "192.0.2.20" }
        end
        assert_equal "Try again later.", flash[:alert]
        assert_redirected_to new_session_path

        travel 15.minutes + 1.second do
          post session_path, params: { email_address: email, password: "wrong" },
            env: { "REMOTE_ADDR" => "192.0.2.20" }
          assert_equal "Try another email address or password.", flash[:alert]
        end
      end
    end
  end

  test "successful login rotates Rails session state and preserves the return destination" do
    get job_path(jobs(:kitchen_renovation))
    assert_redirected_to new_session_path
    previous_id = request.session.id

    post session_path, params: { email_address: @user.email_address, password: "password" }

    assert_redirected_to job_path(jobs(:kitchen_renovation))
    assert_not_equal previous_id, request.session.id
    assert_nil request.session[:return_to_after_authenticating]
  end

  test "successful login removes other preauthentication session data" do
    key = Rails.application.config.session_options[:key]
    cookie_jar = ActionDispatch::TestRequest.create.cookie_jar
    cookie_jar.encrypted[key] = { session_id: SecureRandom.hex(16), unsafe: "old state", _csrf_token: "old token" }
    cookies[key] = cookie_jar[key]

    post session_path, params: { email_address: @user.email_address, password: "password" }

    assert_redirected_to root_path
    assert_nil request.session[:unsafe]
    assert_nil request.session[:_csrf_token]
  end

  test "logging in again rotates the authentication cookie and invalidates its previous session" do
    sign_in_as @user
    previous_session = Current.session
    previous_cookie = cookies[:session_id]
    other_session = @user.sessions.create!

    post session_path, params: { email_address: @user.email_address, password: "password" }

    assert_redirected_to root_path
    assert_not Session.exists?(previous_session.id)
    assert Session.exists?(other_session.id)
    assert_not_equal previous_cookie, cookies[:session_id]

    cookies[:session_id] = previous_cookie
    get jobs_path
    assert_redirected_to new_session_path
  end

  test "authentication cookie is HttpOnly and SameSite Lax" do
    post session_path, params: { email_address: @user.email_address, password: "password" }

    cookie = Array(response.headers["Set-Cookie"]).find { |header| header.start_with?("session_id=") }
    assert cookie
    assert_match(/httponly/i, cookie)
    assert_match(/samesite=lax/i, cookie)
  end

  test "destroy" do
    sign_in_as @user
    previous_session = Current.session
    previous_cookie = cookies[:session_id]
    other_session = @user.sessions.create!
    get jobs_path
    previous_id = request.session.id

    delete session_path

    assert_redirected_to new_session_path
    assert_empty cookies[:session_id]
    assert_not Session.exists?(previous_session.id)
    assert Session.exists?(other_session.id)
    assert_not_equal previous_id, request.session.id

    cookies[:session_id] = previous_cookie
    get jobs_path
    assert_redirected_to new_session_path
  end

  test "a direct password change prevents a previously signed in browser from resuming" do
    sign_in_as @user
    previous_cookie = cookies[:session_id]

    @user.update!(password: "replacement-password")

    cookies[:session_id] = previous_cookie
    get jobs_path
    assert_redirected_to new_session_path

    post session_path, params: { email_address: @user.email_address, password: "password" }
    assert_redirected_to new_session_path

    post session_path, params: { email_address: @user.email_address, password: "replacement-password" }
    assert_redirected_to jobs_path
  end

  private
    def with_rate_limit_cache
      cache = SessionsController.cache_store
      original_increment = cache.method(:increment)
      store = ActiveSupport::Cache::MemoryStore.new
      cache.define_singleton_method(:increment) { |*args, **options| store.increment(*args, **options) }
      yield
    ensure
      cache.define_singleton_method(:increment, original_increment)
    end
end
