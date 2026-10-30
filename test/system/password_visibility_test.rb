require "application_system_test_case"

class PasswordVisibilityTest < ApplicationSystemTestCase
  test "pointer and keyboard toggles preserve the password focus selection and submission" do
    visit new_session_path
    fill_in "Email address", with: users(:one).email_address
    fill_in "Password", with: "password"
    field = find_field("Password")
    field.send_keys([ :shift, :left ])
    selection = field.evaluate_script("[this.selectionStart, this.selectionEnd]")

    click_on "Show password"

    assert_selector '#password[type="text"][autocomplete="current-password"]'
    assert_equal "password", field.value
    assert_selector "#password:focus"
    assert_equal selection, field.evaluate_script("[this.selectionStart, this.selectionEnd]")
    assert_selector '[data-password-visibility-target="hideIcon"] svg'
    assert_no_selector '[data-password-visibility-target="showIcon"] svg'
    assert_current_path new_session_path

    field.send_keys(:tab)
    assert_selector 'button[aria-label="Hide password"]:focus'
    find_button("Hide password").send_keys(:space)
    assert_selector '#password[type="password"]'
    assert_selector 'button[aria-label="Show password"]:focus'
    find_button("Show password").send_keys(:enter)
    assert_selector '#password[type="text"]'
    assert_equal "password", field.value
    find_button("Hide password").send_keys(:tab)
    find_button("Sign in").send_keys(:enter)

    assert_button "Log out"
  end

  test "registration confirmation toggles independently and works after validation errors" do
    visit sign_up_path
    fill_in "Email address", with: "visibility@example.com"
    fill_in "Password", with: "a long passphrase"
    fill_in "Confirm password", with: "another long passphrase"
    click_on "Show password", exact: true
    assert_selector '#user_password[type="text"]'
    assert_selector '#user_password_confirmation[type="password"]'
    click_on "Show confirm password"
    assert_equal "a long passphrase", find_field("Password", exact: true).value
    assert_equal "another long passphrase", find_field("Confirm password").value
    click_on "Create account"

    assert_selector "#user_password_confirmation_error", text: "Password confirmation doesn't match Password"
    assert_selector '[role="alert"]', text: "We couldn’t save your changes."
    assert_field "Email address", with: "visibility@example.com"
    assert_field "Password", with: "", exact: true
    assert_field "Confirm password", with: ""
    assert_selector '#user_password[aria-describedby="password-requirements"]:not([aria-invalid])'
    assert_selector '#user_password_confirmation[aria-invalid="true"][aria-describedby="user_password_confirmation_error"]'
    assert_selector '#user_password[type="password"]'
    assert_selector '#user_password_confirmation[type="password"]'
    fill_in "Password", with: "a long passphrase", exact: true
    fill_in "Confirm password", with: "a long passphrase"
    find_button("Show confirm password").send_keys(:enter)
    assert_selector '#user_password_confirmation[type="text"]'
    click_on "Create account"

    assert_text "Welcome to JobFlow."
    assert User.find_by!(email_address: "visibility@example.com").authenticate("a long passphrase")
  end

  test "password reset visibility works before and after a validation failure" do
    visit edit_password_path(users(:one).password_reset_token)
    fill_in "New password", with: "a replacement passphrase", exact: true
    fill_in "Confirm new password", with: "a different passphrase"
    click_on "Show new password", exact: true
    click_on "Show confirm new password"
    assert_equal "a replacement passphrase", find_field("New password", exact: true).value
    assert_equal "a different passphrase", find_field("Confirm new password").value
    click_on "Save password"

    assert_text "Password confirmation doesn't match Password"
    assert_selector '#password[type="password"]'
    assert_selector '#password_confirmation[type="password"]'
    fill_in "New password", with: "a replacement passphrase", exact: true
    fill_in "Confirm new password", with: "a replacement passphrase"
    click_on "Show new password", exact: true
    click_on "Save password"

    assert_text "Password has been reset."
    assert users(:one).reload.authenticate("a replacement passphrase")
    fill_in "Email address", with: users(:one).email_address
    fill_in "Password", with: "a replacement passphrase"
    click_on "Sign in"
    assert_button "Log out"
  end

  test "Turbo restoration masks revealed fields and initializes each control once" do
    visit new_session_path
    page.execute_script("window.passwordVisibilityNavigationMarker = true")

    2.times do
      fill_in "Password", with: "password"
      click_on "Show password", exact: true
      assert_selector '#password[type="text"]'
      click_on "Create account"
      assert_selector "h1", text: "Create your JobFlow account"
      assert page.evaluate_script("window.passwordVisibilityNavigationMarker === true")
      page.go_back
      assert_current_path new_session_path
      assert_selector '#password[type="password"]'
      assert_button "Show password", count: 1
      assert_no_button "Hide password"
      fill_in "Password", with: "password"
      click_on "Show password", exact: true
      assert_selector '#password[type="text"]'
      assert_equal "password", find_field("Password").value
      click_on "Hide password", exact: true
    end
  end

  test "native paste and copying a revealed password preserve the exact text" do
    visit new_session_path
    origin = URI.join(page.current_url, "/").to_s.delete_suffix("/")
    page.driver.browser.execute_cdp("Browser.grantPermissions", origin: origin,
      permissions: [ "clipboardReadWrite", "clipboardSanitizedWrite" ])
    password = " A long passphrase 42! "
    assert_nil page.evaluate_async_script("navigator.clipboard.writeText(arguments[0]).then(() => arguments[1](null), error => arguments[1](error.name))", password)
    find_field("Password").send_keys([ :control, "v" ])
    assert_field "Password", with: password
    click_on "Show password", exact: true
    find_field("Password").send_keys([ :control, "a" ], [ :control, "c" ])
    assert_equal password, page.evaluate_async_script("navigator.clipboard.readText().then(arguments[0])")
    click_on "Hide password", exact: true
    assert_field "Password", with: password
  ensure
    page.evaluate_async_script("navigator.clipboard.writeText('').then(arguments[0], arguments[0])")
    page.driver.browser.execute_cdp("Browser.resetPermissions")
  end
end
