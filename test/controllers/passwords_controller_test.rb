require "test_helper"

class PasswordsControllerTest < ActionDispatch::IntegrationTest
  setup { @user = User.take }

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
      put password_path(@user.password_reset_token), params: { password: "new", password_confirmation: "new" }
      assert_redirected_to new_session_path
    end

    follow_redirect!
    assert_notice "Password has been reset"
  end

  test "update with non matching passwords" do
    token = @user.password_reset_token
    assert_no_changes -> { @user.reload.password_digest } do
      put password_path(token), params: { password: "no", password_confirmation: "match" }
      assert_redirected_to edit_password_path(token)
    end

    follow_redirect!
    assert_notice "Passwords did not match"
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
        put password_path(token), params: { password: "replacement", password_confirmation: "replacement" }
      end
      assert_redirected_to new_password_path
    end
  end

  test "invalid tokens cannot update a password" do
    assert_no_changes -> { @user.reload.password_digest } do
      put password_path("invalid"), params: { password: "replacement", password_confirmation: "replacement" }
    end
    assert_redirected_to new_password_path
  end

  test "known and unknown accounts receive the same response" do
    post passwords_path, params: { email_address: @user.email_address }
    notice = flash[:notice]
    location = response.location
    assert_no_enqueued_jobs only: PasswordResetDeliveryJob do
      post passwords_path, params: { email_address: "missing-user@example.com" }
    end
    assert_equal location, response.location
    assert_equal notice, flash[:notice]
  end

  private
    def assert_notice(text)
      assert_select "div", /#{text}/
    end
end
