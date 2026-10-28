require "test_helper"

class AccountsControllerTest < ActionDispatch::IntegrationTest
  test "account requires authentication" do
    get account_path
    assert_redirected_to new_session_path
  end

  test "account shows only the signed in user's details and disabled status" do
    sign_in_as users(:one)
    get account_path, params: { user_id: users(:two).id }

    assert_response :success
    assert_select "h1", "Account"
    assert_select "dd", users(:one).email_address
    refute_includes response.body, users(:two).email_address
    assert_select "section[aria-labelledby=security-heading]", text: /Not enabled/
    assert_select "a[href=?]", account_security_path, text: "Enable two-factor authentication"
    assert_select "nav a[href=?]", account_path, text: "Account"
    assert_includes response.headers["Cache-Control"], "no-store"
    assert_select 'meta[name="turbo-cache-control"][content="no-cache"]'
  end

  test "account shows enabled status without revealing credentials" do
    secret = ROTP::Base32.random
    codes = users(:one).enable_two_factor!(secret: secret, code: ROTP::TOTP.new(secret).now)
    sign_in_as users(:one)
    get account_path

    assert_response :success
    assert_select "section[aria-labelledby=security-heading]", text: /Enabled/
    assert_select "a[href=?]", account_security_path, text: "Manage two-factor authentication"
    [ secret, *codes ].each { |credential| refute_includes response.body, credential }
  end
end
