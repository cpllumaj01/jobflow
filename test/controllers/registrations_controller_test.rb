require "test_helper"

class RegistrationsControllerTest < ActionDispatch::IntegrationTest
  test "new" do
    get sign_up_url
    assert_response :success
  end

  test "create" do
    assert_difference [ "User.count", "Session.count" ], 1 do
      post sign_up_url, params: {
        user: {
          email_address: "new@example.com",
          password: "passwordpassword",
          password_confirmation: "passwordpassword"
        }
      }
  end

    assert_redirected_to root_url
  end

  test "create with invalid user" do
    assert_no_difference "User.count" do
      post sign_up_url, params: {
        user: {
          email_address: "new@example.com",
          password: "passwordpassword",
          password_confirmation: "different-password"
        }
      }
    end

    assert_response :unprocessable_entity
    assert_select '#user_password_confirmation[aria-invalid="true"][aria-describedby="user_password_confirmation_error"]'
    assert_select "#user_password_confirmation_error", text: "Password confirmation doesn't match Password"
    assert_select 'input[type="password"][value]', count: 0
  end

  test "create rejects a short password without creating an account or session" do
    assert_no_difference [ "User.count", "Session.count" ] do
      post sign_up_url, params: {
        user: {
          email_address: "new@example.com",
          password: "short-password",
          password_confirmation: "short-password"
        }
      }
    end

    assert_response :unprocessable_entity
    assert_select "#user_password_error", /Password is too short/
    assert_select '#user_password[aria-invalid="true"][aria-describedby="password-requirements user_password_error"]'
    assert_select "#password-requirements", text: /Use at least 15 characters/
    assert_select 'input[type="password"][value]', count: 0
    assert_nil cookies[:session_id]
  end

  test "duplicate email has one inline message and leaves valid fields unmarked" do
    post sign_up_url, params: { user: {
      email_address: users(:one).email_address, password: "a long passphrase", password_confirmation: "a long passphrase"
    } }

    assert_response :unprocessable_entity
    assert_select '#user_email_address[aria-invalid="true"][aria-describedby="user_email_address_error"]'
    assert_select "#user_email_address_error", text: "Email address has already been taken"
    assert_select '#user_password[aria-describedby="password-requirements"]:not([aria-invalid])'
    assert_select '[role="alert"] li', count: 0
  end
end
