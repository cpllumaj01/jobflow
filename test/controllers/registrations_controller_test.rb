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
    assert_select "li", /Password is too short/
    assert_nil cookies[:session_id]
  end
end
