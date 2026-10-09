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
          password: "password",
          password_confirmation: "password"
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
          password: "password",
          password_confirmation: "different"
        }
      }
    end

    assert_response :unprocessable_entity
  end
end
