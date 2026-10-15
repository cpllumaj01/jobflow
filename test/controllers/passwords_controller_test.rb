require "test_helper"

class PasswordsControllerTest < ActionDispatch::IntegrationTest
  setup { @user = users(:one) }

  test "new" do
    get new_password_path
    assert_response :success
  end

  test "create" do
    assert_enqueued_with job: PasswordResetDeliveryJob do
      post passwords_path, params: { email_address: @user.email_address }
    end

    assert_redirected_to new_session_path

    follow_redirect!
    assert_notice "reset instructions sent"
  end

  test "create for an unknown user redirects but sends no mail" do
    assert_no_enqueued_jobs only: PasswordResetDeliveryJob do
      post passwords_path, params: { email_address: "missing-user@example.com" }
    end

    assert_redirected_to new_session_path

    follow_redirect!
    assert_notice "reset instructions sent"
  end

  test "malformed email addresses receive the generic response without sending mail" do
    post passwords_path, params: { email_address: "missing-user@example.com" }
    notice = flash[:notice]

    [ [ @user.email_address ], { value: @user.email_address } ].each do |email_address|
      assert_no_enqueued_jobs only: PasswordResetDeliveryJob do
        post passwords_path, params: { email_address: email_address }
      end

      assert_redirected_to new_session_path
      assert_equal notice, flash[:notice]
    end
  end

  test "edit" do
    get edit_password_path(@user.password_reset_token)
    assert_response :success
  end

  test "edit with invalid password reset token" do
    get edit_password_path("invalid token")
    assert_redirected_to new_password_path

    follow_redirect!
    assert_notice "reset link is invalid"
  end

  test "update" do
    assert_changes -> { @user.reload.password_digest } do
      put password_path(@user.password_reset_token), params: { password: "replacement-password", password_confirmation: "replacement-password" }
      assert_redirected_to new_session_path
    end

    follow_redirect!
    assert_notice "Password has been reset"
  end

  test "update with non matching passwords" do
    token = @user.password_reset_token

    assert_no_changes -> { @user.reload.password_digest } do
      put password_path(token), params: { password: "replacement-password", password_confirmation: "different-password" }
      assert_redirected_to edit_password_path(token)
    end

    follow_redirect!
    assert_notice "Password confirmation doesn't match Password"
  end

  test "missing empty and malformed passwords leave the account and reset token unchanged" do
    token = @user.password_reset_token
    session = @user.sessions.create!
    invalid_params = [
      {},
      { password: "", password_confirmation: "" },
      { password: [ "replacement-password" ], password_confirmation: "replacement-password" },
      { password: { value: "replacement-password" }, password_confirmation: "replacement-password" }
    ]

    invalid_params.each do |password_params|
      assert_no_changes -> { @user.reload.password_digest } do
        put password_path(token), params: password_params
      end

      assert_redirected_to edit_password_path(token)
      assert_equal "Password can't be blank.", flash[:alert]
      assert Session.exists?(session.id)
      assert_equal @user, User.find_by_password_reset_token(token)

      get edit_password_path(token)
      assert_response :success
    end
  end

  test "short and oversized passwords display validation errors without consuming the token" do
    token = @user.password_reset_token
    session = @user.sessions.create!

    { "short-password" => "Password is too short", "a" * 73 => "Password is too long" }.each do |password, message|
      assert_no_changes -> { @user.reload.password_digest } do
        put password_path(token), params: { password: password, password_confirmation: password }
      end

      assert_redirected_to edit_password_path(token)
      assert_includes flash[:alert], message
      assert Session.exists?(session.id)
      assert_equal @user, User.find_by_password_reset_token(token)
    end
  end

  test "a successful reset rejects token reuse and invalidates previously issued tokens" do
    token = @user.password_reset_token
    other_token = travel(1.second) { @user.password_reset_token }

    put password_path(token), params: { password: "replacement-password", password_confirmation: "replacement-password" }
    assert_redirected_to new_session_path

    [ token, other_token ].each do |used_token|
      assert_nil User.find_by_password_reset_token(used_token)

      assert_no_changes -> { @user.reload.password_digest } do
        put password_path(used_token), params: { password: "another-password", password_confirmation: "another-password" }
      end

      assert_redirected_to new_password_path
    end

    assert @user.reload.authenticate("replacement-password")
    assert_equal @user, User.find_by_password_reset_token(@user.password_reset_token)
  end

  test "resetting a password rejects old cookies from every signed in browser" do
    first_browser = open_session
    second_browser = open_session
    other_browser = open_session

    [ first_browser, second_browser ].each do |browser|
      browser.post session_path, params: { email_address: @user.email_address, password: "password" }
      browser.assert_redirected_to root_path
    end
    other_browser.post session_path, params: { email_address: users(:two).email_address, password: "password" }
    other_cookie = other_browser.cookies[:session_id]

    put password_path(@user.password_reset_token), params: { password: "replacement-password", password_confirmation: "replacement-password" }
    assert_redirected_to new_session_path
    assert_empty @user.sessions.reload

    [ first_browser, second_browser ].each do |browser|
      assert browser.cookies[:session_id]
      browser.get root_path
      browser.assert_redirected_to new_session_path
    end

    other_browser.get root_path
    other_browser.assert_response :success
    assert_equal other_cookie, other_browser.cookies[:session_id]
    assert_equal 1, users(:two).sessions.count
  end

  test "resetting the signed in user's password clears their cookie and rotates the Rails session" do
    post session_path, params: { email_address: @user.email_address, password: "password" }
    get edit_password_path("invalid")
    previous_session_id = request.session.id.public_id

    put password_path(@user.password_reset_token), params: { password: "replacement-password", password_confirmation: "replacement-password" }

    assert_redirected_to new_session_path
    assert_empty cookies[:session_id]
    assert_not_equal previous_session_id, request.session.id.public_id
    assert_empty @user.sessions.reload

    get root_path
    assert_redirected_to new_session_path
  end

  test "resetting another account's password preserves the signed in user's session" do
    post session_path, params: { email_address: users(:two).email_address, password: "password" }
    get edit_password_path("invalid")
    previous_session_id = request.session.id.public_id
    previous_cookie = cookies[:session_id]

    put password_path(@user.password_reset_token), params: { password: "replacement-password", password_confirmation: "replacement-password" }

    assert_redirected_to new_session_path
    assert_equal previous_cookie, cookies[:session_id]
    assert_equal previous_session_id, request.session.id.public_id
    assert_equal 1, users(:two).sessions.count

    get root_path
    assert_response :success
  end

  test "a password change between token lookup and reset prevents the reset from proceeding" do
    token = @user.password_reset_token
    original_lookup = User.method(:find_by_password_reset_token!)
    lookups = 0

    User.define_singleton_method(:find_by_password_reset_token!) do |submitted_token|
      user = original_lookup.call(submitted_token)
      lookups += 1
      user.update!(password: "concurrent-password") if lookups == 1
      user
    end

    put password_path(token), params: { password: "replacement-password", password_confirmation: "replacement-password" }

    assert_redirected_to new_password_path
    assert @user.reload.authenticate("concurrent-password")
    assert_not @user.authenticate("replacement-password")
  ensure
    User.define_singleton_method(:find_by_password_reset_token!, original_lookup)
  end

  test "request delivers a usable reset link and resetting preserves sign in behavior" do
    @user.sessions.create!(user_agent: "test", ip_address: "127.0.0.1")

    assert_emails 1 do
      perform_enqueued_jobs do
        post passwords_path, params: { email_address: @user.email_address }
      end
    end

    mail = ActionMailer::Base.deliveries.last
    assert_equal [ @user.email_address ], mail.to

    link = mail.text_part.body.decoded.match(%r{http://example.com(/passwords/[^/]+/edit)})[1]

    get link
    assert_response :success

    token = request.path_parameters[:token]

    put password_path(token), params: { password: "replacement-password", password_confirmation: "replacement-password" }
    assert_redirected_to new_session_path

    assert_empty @user.sessions.reload
    assert @user.reload.authenticate("replacement-password")
    assert_nil User.find_by_password_reset_token(token)

    post session_path, params: { email_address: @user.email_address, password: "replacement-password" }
    assert_redirected_to root_path
    assert cookies[:session_id]
  end

  test "expired tokens cannot display the form or update a password" do
    token = @user.password_reset_token

    travel @user.password_reset_token_expires_in + 1.second do
      get edit_password_path(token)
      assert_redirected_to new_password_path

      assert_no_changes -> { @user.reload.password_digest } do
        put password_path(token), params: { password: "replacement-password", password_confirmation: "replacement-password" }
      end

      assert_redirected_to new_password_path
    end
  end

  test "invalid tokens cannot update a password" do
    assert_no_changes -> { @user.reload.password_digest } do
      put password_path("invalid"), params: { password: "replacement-password", password_confirmation: "replacement-password" }
    end

    assert_redirected_to new_password_path
  end

  test "known and unknown accounts receive the same response" do
    post passwords_path, params: { email_address: @user.email_address }

    notice = flash[:notice]
    location = response.location
    status = response.status

    follow_redirect!
    existing_account_page = response.body

    assert_no_enqueued_jobs only: PasswordResetDeliveryJob do
      post passwords_path, params: { email_address: "missing-user@example.com" }
    end

    assert_equal location, response.location
    assert_equal status, response.status
    assert_equal notice, flash[:notice]

    follow_redirect!
    assert_equal existing_account_page, response.body
  end

  private

    def assert_notice(text)
      assert_select "div", /#{text}/
    end
end
