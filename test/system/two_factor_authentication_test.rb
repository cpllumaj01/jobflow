require "application_system_test_case"

class TwoFactorAuthenticationTest < ApplicationSystemTestCase
  setup do
    @previous_forgery_protection = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
  end

  teardown do
    ActionController::Base.allow_forgery_protection = @previous_forgery_protection
  end

  test "canceling authenticator setup clears pending credentials" do
    visit new_session_path
    fill_in "Email address", with: users(:one).email_address
    fill_in "Password", with: "password"
    click_on "Sign in"
    click_on "Account security"
    assert_selector "h1", text: "Account security"
    fill_in "Current password", with: "password"
    click_on "Set up two-factor authentication"
    assert_text "Set up your authenticator"
    assert users(:one).reload.otp_setup_secret.present?

    click_on "Cancel setup"

    assert_selector "h1", text: "Account security"
    assert_nil users(:one).reload.otp_setup_secret
    assert_not users(:one).two_factor_enabled?
  end

  test "authenticator sign in permits retry after an invalid code" do
    secret = ROTP::Base32.random
    travel_to 1.minute.ago do
      users(:one).enable_two_factor!(secret: secret, code: ROTP::TOTP.new(secret).now)
    end
    visit new_session_path
    fill_in "Email address", with: users(:one).email_address
    fill_in "Password", with: "password"
    click_on "Sign in"
    assert_text "Verify your sign-in"
    fill_in "Authenticator or recovery code", with: "invalid"
    click_on "Verify sign-in"
    assert_text "Invalid or already used code."
    fill_in "Authenticator or recovery code", with: ROTP::TOTP.new(secret).now
    click_on "Verify sign-in"
    assert_button "Log out"
  end

  test "account security setup recovery sign in regeneration and disabling on a phone" do
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
      width: 375, height: 1000, deviceScaleFactor: 1, mobile: false)
    visit new_session_path
    fill_in "Email address", with: users(:one).email_address
    fill_in "Password", with: "password"
    click_on "Sign in"
    click_on "Account security"
    assert_selector "h1", text: "Account security"
    fill_in "Current password", with: "password"
    click_on "Set up two-factor authentication"
    assert_text "Set up your authenticator"
    secret = find('[aria-label="Setup key"]').text
    assert_fits_phone
    fill_in "Authenticator code", with: ROTP::TOTP.new(secret).at(2.minutes.ago)
    click_on "Enable two-factor authentication"
    assert_text "Enter a valid authenticator code."
    assert_not users(:one).reload.two_factor_enabled?
    fill_in "Authenticator code", with: ROTP::TOTP.new(secret).now
    click_on "Enable two-factor authentication"
    assert_text "Save your recovery codes"
    codes = all('ul[aria-label="Recovery codes"] li').map(&:text)
    assert_equal 10, codes.size
    assert_fits_phone
    click_on "I've saved my codes"
    click_on "Log out"

    fill_in "Email address", with: users(:one).email_address
    fill_in "Password", with: "password"
    click_on "Sign in"
    assert_text "Verify your sign-in"
    assert_no_button "Log out"
    assert_fits_phone
    fill_in "Authenticator or recovery code", with: codes.first
    click_on "Verify sign-in"
    assert_button "Log out"
    click_on "Account security"
    assert_text "9 recovery codes remaining."
    assert_fits_phone
    within "form[action='#{recovery_codes_account_security_path}']" do
      fill_in "Current password", with: "password"
      fill_in "Authenticator or recovery code", with: codes.last
      click_on "Regenerate recovery codes"
    end
    assert_text "Save your recovery codes"
    replacement = all('ul[aria-label="Recovery codes"] li').map(&:text)
    assert_equal 10, replacement.size
    assert_empty codes & replacement
    click_on "I've saved my codes"
    within "form[action='#{two_factor_account_security_path}']" do
      fill_in "Current password", with: "password"
      fill_in "Authenticator or recovery code", with: replacement.first
      click_on "Disable 2FA"
    end
    assert_text "Two-factor authentication disabled."
    assert_button "Set up two-factor authentication"
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  private
    def assert_fits_phone
      assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, 375
    end
end
