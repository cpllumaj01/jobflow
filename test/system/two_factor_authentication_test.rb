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
    open_account_security
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
    open_account_security
    assert_selector "h1", text: "Account security"
    fill_in "Current password", with: "password"
    assert_password_visibility
    click_on "Set up two-factor authentication"
    assert_text "Set up your authenticator"
    qr = find('img[alt="Scan this QR code with your authenticator app"]')
    assert qr["src"].start_with?("data:image/svg+xml;base64,")
    assert qr.evaluate_script("this.complete && this.naturalWidth > 0")
    find("summary", text: "Can't scan? Enter a setup key").send_keys(:enter)
    secret = find('[aria-label="Setup key"]').text
    assert_fits_phone
    fill_in "Authenticator code", with: ROTP::TOTP.new(secret).at(2.minutes.ago)
    click_on "Enable two-factor authentication"
    assert_text "Enter a valid authenticator code."
    assert_not users(:one).reload.two_factor_enabled?
    fill_in "Authenticator code", with: ROTP::TOTP.new(secret).now
    click_on "Enable two-factor authentication"
    assert_selector "h1", text: "Two-factor authentication is enabled"
    codes = all('ul[aria-label="Recovery codes"] li').map(&:text)
    assert_equal 10, codes.size
    assert_fits_phone
    click_on "Skip for now"
    assert_current_path account_path
    assert_no_selector 'ul[aria-label="Recovery codes"]'
    assert_link "Manage two-factor authentication"
    page.go_back
    assert_no_selector 'ul[aria-label="Recovery codes"] li', text: codes.first
    visit account_path
    click_on "Menu"
    click_on "Log out"

    fill_in "Email address", with: users(:one).email_address
    fill_in "Password", with: "password"
    click_on "Sign in"
    assert_text "Verify your sign-in"
    assert_no_button "Log out"
    assert_fits_phone
    fill_in "Authenticator or recovery code", with: codes.first
    click_on "Verify sign-in"
    assert_button "Menu"
    open_account_security
    assert_text "9 recovery codes remaining."
    assert_fits_phone
    within "form[action='#{recovery_codes_account_security_path}']" do
      fill_in "Current password", with: "password"
      assert_password_visibility
      fill_in "Authenticator or recovery code", with: codes.last
      click_on "Regenerate recovery codes"
    end
    assert_selector "h1", text: "Two-factor authentication is enabled"
    replacement = all('ul[aria-label="Recovery codes"] li').map(&:text)
    assert_equal 10, replacement.size
    assert_empty codes & replacement
    click_on "Skip for now"
    assert_current_path account_path
    click_on "Manage two-factor authentication"
    within "form[action='#{two_factor_account_security_path}']" do
      fill_in "Current password", with: "password"
      assert_password_visibility
      fill_in "Authenticator or recovery code", with: replacement.first
      click_on "Disable 2FA"
    end
    assert_text "Two-factor authentication disabled."
    assert_button "Set up two-factor authentication"
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  test "recovery codes can be copied downloaded or left without saving" do
    download_directory = Dir.mktmpdir("jobflow-recovery-test")
    page.driver.browser.execute_cdp("Browser.setDownloadBehavior", behavior: "allow", downloadPath: download_directory)
    visit new_session_path
    fill_in "Email address", with: users(:one).email_address
    fill_in "Password", with: "password"
    click_on "Sign in"
    open_account_security
    fill_in "Current password", with: "password"
    click_on "Set up two-factor authentication"
    assert_selector "h1", text: "Set up your authenticator"
    fill_in "Authenticator code", with: ROTP::TOTP.new(users(:one).reload.otp_setup_secret).now
    click_on "Enable two-factor authentication"
    assert_selector "h1", text: "Two-factor authentication is enabled"
    codes = all('ul[aria-label="Recovery codes"] li').map(&:text)

    origin = URI.join(page.current_url, "/").to_s.delete_suffix("/")
    page.driver.browser.execute_cdp("Browser.grantPermissions", origin: origin,
      permissions: [ "clipboardReadWrite", "clipboardSanitizedWrite" ])
    find_button("Copy", exact: true).send_keys(:enter)
    assert_selector '[role="status"]', text: "Recovery codes copied."
    clipboard = page.evaluate_async_script("navigator.clipboard.readText().then(arguments[0])")
    assert_equal codes.join("\n"), clipboard

    click_on "Download", exact: true
    file = File.join(download_directory, "jobflow-recovery-codes.txt")
    assert_selector '[role="status"]', text: "Recovery codes downloaded." do
      File.exist?(file)
    end
    assert_equal "JobFlow recovery codes\n\n#{codes.join("\n")}\n", File.read(file)
    assert_equal 10, users(:one).reload.recovery_code_digests.size
    assert_equal "{}", page.evaluate_script("JSON.stringify(localStorage)")
    assert_equal "{}", page.evaluate_script("JSON.stringify(sessionStorage)")

    page.execute_script("navigator.clipboard.writeText = () => Promise.reject(new Error('denied'))")
    click_on "Copy", exact: true
    assert_selector '[role="status"]', text: "Couldn't copy the codes."
    assert_button "Download"

    click_on "Continue to JobFlow"
    assert_current_path root_path
    page.go_back
    assert_no_selector 'ul[aria-label="Recovery codes"] li', text: codes.first
    visit account_path
    assert_link "Manage two-factor authentication"
    assert_no_selector 'ul[aria-label="Recovery codes"]'
  ensure
    page.execute_script("delete navigator.clipboard.writeText")
    page.driver.browser.execute_cdp("Browser.resetPermissions")
    page.driver.browser.execute_cdp("Browser.setDownloadBehavior", behavior: "default")
    FileUtils.remove_entry(download_directory) if download_directory
  end

  private
    def open_account_security
      click_on "Menu" if page.evaluate_script("window.innerWidth < 768")
      within 'nav[aria-label="Main navigation"]' do
        click_on "Account", exact: true
      end
      assert_selector "h1", text: "Account", exact_text: true
      assert_text users(:one).email_address
      click_on users(:one).reload.two_factor_enabled? ? "Manage two-factor authentication" : "Enable two-factor authentication"
    end

    def assert_password_visibility
      field = find_field("Current password")
      assert_equal "password", field["type"]
      button = find_button("Show current password")
      size = button.evaluate_script("[this.getBoundingClientRect().width, this.getBoundingClientRect().height]")
      assert_operator size[0], :>=, 44
      assert_operator size[1], :>=, 44
      button.click
      assert_selector 'input[type="text"][autocomplete="current-password"]'
      assert_equal "password", field.value
      find_button("Hide current password").send_keys(:space)
      assert_selector 'input[type="password"][autocomplete="current-password"]'
      find_button("Show current password").send_keys(:enter)
      assert_selector 'input[type="text"][autocomplete="current-password"]'
      assert_equal "password", field.value
    end

    def assert_fits_phone
      assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, 375
    end
end
