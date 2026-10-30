require "application_system_test_case"

class FormValidationTest < ApplicationSystemTestCase
  setup do
    visit new_session_path
    fill_in "Email address", with: users(:one).email_address
    fill_in "Password", with: "password"
    click_on "Sign in"
    assert_button "Log out"
  end

  test "customer and job validation failures can be corrected using the keyboard" do
    visit new_customer_path
    fill_in "Contact name", with: "Sam Contractor"
    click_on "Create Customer"

    assert_inline_error "customer_name", "Name can't be blank"
    assert_field "Contact name", with: "Sam Contractor"
    assert_error_layout "customer"
    find_field("Name").click
    assert_selector "#customer_name:focus"
    fill_in "Name", with: "New customer"
    find_field("Name").send_keys(:tab)
    assert_selector "#customer_contact_name:focus"
    click_on "Create Customer"
    assert_text "Customer was successfully created."

    visit new_job_path
    fill_in "Description", with: "A detailed scope of work"
    click_on "Create Job"
    assert_inline_error "job_name", "Name can't be blank"
    assert_field "Description", with: "A detailed scope of work"
    assert_selector '#job_estimated_completion_date[aria-describedby="estimated-completion-help"]:not([aria-invalid])'
    assert_error_layout "job"
    fill_in "Name", with: "New project"
    click_on "Create Job"
    assert_text "Job was successfully created."
  end

  test "registration errors wrap on small screens while requirements and password controls remain usable" do
    click_on "Log out"
    visit sign_up_path
    fill_in "Email address", with: users(:one).email_address
    fill_in "Password", with: "a long passphrase", exact: true
    fill_in "Confirm password", with: "a different passphrase"
    click_on "Create account"

    assert_inline_error "user_email_address", "Email address has already been taken"
    assert_inline_error "user_password_confirmation", "Password confirmation doesn't match Password"
    assert_field "Password", with: "", exact: true
    assert_field "Confirm password", with: ""
    assert_selector '#user_password[aria-describedby="password-requirements"]:not([aria-invalid])'
    assert_error_layout "registration"
    fill_in "Email address", with: "corrected@example.com"
    fill_in "Password", with: "a long passphrase", exact: true
    fill_in "Confirm password", with: "a long passphrase"
    click_on "Show password", exact: true
    assert_selector '#user_password[type="text"]'
    click_on "Create account"
    assert_text "Welcome to JobFlow."
  end

  %w[estimate change_order].each do |resource|
    test "#{resource} rows have independent errors and allow adding removing and correcting after Turbo submission" do
      job = customers(:johnson).jobs.create!(name: "Project needing a proposal")
      visit resource == "estimate" ? new_job_estimate_path(job) : new_job_change_order_path(job)
      page.execute_script("window.validationNavigationMarker = true")
      rows = "[data-nested-line-items-target=items] [data-testid=line-item]"
      within first(rows) do
        fill_in "Quantity", with: "0"
        fill_in "Unit price", with: "-1"
      end
      click_on "Add line item"
      within all(rows).last do
        fill_in "Description", with: "Additional materials"
        fill_in "Quantity", with: "-2"
      end
      submit = resource == "estimate" ? "Create Estimate" : "Create Change order"
      click_on submit

      assert_selector '[role="alert"]', text: "We couldn’t save your changes."
      assert page.evaluate_script("window.validationNavigationMarker === true")
      assert_selector rows, count: 2
      assert_selector "#{rows} [aria-invalid=true]", count: 5
      assert_inline_error "#{resource}_title", "Title can't be blank" if resource == "change_order"
      within all(rows).first do
        assert_field "Description", with: ""
        assert_field "Quantity", with: "0"
        assert_field "Unit price", with: "-1"
      end
      within all(rows).last do
        assert_field "Description", with: "Additional materials"
        assert_field "Quantity", with: "-2"
        assert_field "Unit price", with: ""
      end
      ids = all("[id]", visible: :all).map { |element| element[:id] }
      assert_equal ids.uniq, ids
      assert_error_layout resource

      click_on "Add line item"
      assert_selector rows, count: 3
      within all(rows).last do
        assert_no_selector '[aria-invalid="true"]'
        click_on "Remove"
      end
      assert_selector rows, count: 2
      all(rows).each_with_index do |row, index|
        within row do
          %w[description quantity unit_price].each do |field|
            input = find("input[name$='[#{field}]']")
            if input["aria-invalid"] == "true"
              assert_inline_error input[:id], /#{field.humanize}/
            end
          end
          fill_in "Description", with: "Corrected row #{index + 1}"
          fill_in "Quantity", with: "2"
          fill_in "Unit price", with: "25"
        end
      end
      fill_in "Title", with: "Extra work" if resource == "change_order"
      click_on submit
      assert_text "successfully created"
      assert_text "Corrected row 1"
      assert_text "Corrected row 2"
    end
  end

  private
    def assert_inline_error(id, message)
      assert_selector "##{id}[aria-invalid=true][aria-describedby~='#{id}_error']"
      assert_selector "##{id}_error", text: message
    end

    def assert_error_layout(context)
      [ 320, 375, 430, 768, 1400 ].each do |width|
        page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
          width: width, height: 1000, deviceScaleFactor: 1, mobile: false)
        assert_equal width, page.evaluate_script("window.innerWidth")
        assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth"), "#{context} overflows at #{width}px"
        all('p[id$="_error"], [role="alert"]').each do |message|
          assert message.evaluate_script("this.scrollWidth <= this.clientWidth"), "#{context} error clips at #{width}px"
        end
        invalid = first('[aria-invalid="true"]')
        valid = first('input:not([aria-invalid]):not([type="hidden"]):not([type="submit"])')
        if invalid && valid
          refute_equal valid.evaluate_script("getComputedStyle(this).borderColor"), invalid.evaluate_script("getComputedStyle(this).borderColor")
        end
        if width >= 1024
          all('[data-testid="line-item"]').each do |row|
            tops = row.all('input:not([type="hidden"])').map { |input| input.evaluate_script("this.getBoundingClientRect().top") }
            assert_operator tops.max - tops.min, :<=, 1, "Line item inputs should align when error messages wrap"
          end
        end
      end
    ensure
      page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    end
end
