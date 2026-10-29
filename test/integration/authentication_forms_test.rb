require "test_helper"

class AuthenticationFormsTest < ActionDispatch::IntegrationTest
  test "sign in pairs email and current password in one form" do
    get new_session_path

    assert_input "email_address", name: "email_address", type: "email", autocomplete: "username"
    assert_input "password", name: "password", type: "password", autocomplete: "current-password"
    assert_select "form[action=?]", session_url do
      assert_select "#email_address[required][autofocus]"
      assert_select '#password[required][maxlength="72"]'
    end
    assert_form_semantics
  end

  test "registration identifies username and both new password fields including after validation errors" do
    get sign_up_path
    assert_registration_fields

    post sign_up_path, params: { user: {
      email_address: "new@example.com", password: "a long passphrase", password_confirmation: "another long passphrase"
    } }

    assert_response :unprocessable_entity
    assert_select '[role="alert"]', /Password confirmation doesn't match Password/
    assert_select '#user_email_address[value="new@example.com"]'
    assert_registration_fields
  end

  test "reset request identifies the email as a username" do
    get new_password_path

    assert_input "email_address", name: "email_address", type: "email", autocomplete: "username"
    assert_select 'input[type="password"]', count: 0
    assert_form_semantics
  end

  test "password reset pairs new passwords with the token owner even when another user is signed in" do
    sign_in_as users(:two)
    token = users(:one).password_reset_token
    get edit_password_path(token)

    assert_input "password", name: "password", type: "password", autocomplete: "new-password"
    assert_input "password_confirmation", name: "password_confirmation", type: "password", autocomplete: "new-password"
    assert_select "form[action=?]", password_path(token) do
      assert_input "reset_email_address", name: "email_address", type: "hidden", autocomplete: "username"
      assert_select "#reset_email_address[value=?]", users(:one).email_address
      assert_select '#password[minlength="15"][aria-describedby="password-requirements"]'
      assert_select '#password_confirmation[maxlength="72"]'
    end
    assert_form_semantics
  end

  test "account setup pairs the current password with the authenticated account" do
    sign_in_as users(:one)
    get account_security_path

    assert_select "form[action=?]", setup_account_security_path do
      assert_security_fields "setup"
    end
    assert_form_semantics

    post setup_account_security_path, params: { password: "password" }
    assert_input "verification_code", name: "verification_code", type: "text", autocomplete: "one-time-code"
    assert_select '#verification_code[inputmode="numeric"][pattern="[0-9]{6}"][maxlength="6"]'
    assert_select '[data-controller="password-visibility"]', count: 0
    assert_form_semantics
  end

  test "regeneration and disabling keep independent password username and verification fields" do
    enable_two_factor
    sign_in_as users(:one)
    get account_security_path

    { "regeneration" => recovery_codes_account_security_path, "disable" => two_factor_account_security_path }.each do |prefix, path|
      assert_select "form[action=?]", path do
        assert_security_fields prefix
        assert_input "#{prefix}_code", name: "verification_code", type: "text", autocomplete: "one-time-code"
        assert_select "##{prefix}_code[spellcheck=false][autocapitalize=none]"
      end
    end
    assert_form_semantics
  end

  test "the sign in challenge treats authenticator and recovery codes as text" do
    enable_two_factor
    post session_path, params: { email_address: users(:one).email_address, password: "password" }
    get new_two_factor_challenge_path

    assert_input "verification_code", name: "verification_code", type: "text", autocomplete: "one-time-code"
    assert_select "#verification_code[spellcheck=false][autocapitalize=none]"
    assert_select 'input[type="password"]', count: 0
    assert_select '[data-controller="password-visibility"]', count: 0
    assert_form_semantics
  end

  private
    def assert_input(id, name:, type:, autocomplete:)
      assert_select "input[id=?][name=?][type=?][autocomplete=?]", id, name, type, autocomplete, count: 1
    end

    def assert_registration_fields
      assert_input "user_email_address", name: "user[email_address]", type: "email", autocomplete: "username"
      assert_input "user_password", name: "user[password]", type: "password", autocomplete: "new-password"
      assert_input "user_password_confirmation", name: "user[password_confirmation]", type: "password", autocomplete: "new-password"
      assert_select '#user_password[minlength="15"][aria-describedby="password-requirements"]'
      assert_form_semantics
    end

    def assert_security_fields(prefix)
      assert_input "#{prefix}_email_address", name: "email_address", type: "hidden", autocomplete: "username"
      assert_select "##{prefix}_email_address[value=?]", users(:one).email_address
      assert_input "#{prefix}_password", name: "password", type: "password", autocomplete: "current-password"
      assert_select "##{prefix}_password[maxlength='72']"
    end

    def assert_form_semantics
      ids = css_select("[id]").map { |element| element["id"] }
      assert_equal ids.uniq, ids, "IDs must be unique on each page"
      css_select('input:not([type="hidden"]):not([type="submit"])').each do |input|
        assert input["id"].present?
        assert_select "label[for=?]", input["id"], count: 1
        assert_select "form input[id=?]", input["id"], count: 1
      end
      css_select('input[type="password"]').each do |input|
        assert_select 'button[type="button"][aria-controls=?][aria-label^="Show "]', input["id"], count: 1
      end
      assert_select '[autocomplete="off"]', count: 0
    end

    def enable_two_factor
      secret = ROTP::Base32.random
      users(:one).enable_two_factor!(secret: secret, code: ROTP::TOTP.new(secret).now)
    end
end
