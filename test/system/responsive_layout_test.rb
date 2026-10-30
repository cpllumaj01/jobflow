require "application_system_test_case"

class ResponsiveLayoutTest < ApplicationSystemTestCase
  setup do
    @customer = customers(:johnson)
    @job = jobs(:kitchen_renovation)
    @change_order = change_orders(:kitchen_lighting)
    @customer.update!(name: "Johnson Residence and Workshop", contact_name: "Sarah Johnson, property management and renovations", email: "#{'longaddress' * 5}@example.com")
    @job.update!(name: "Kitchen renovation and workshop improvements", address: "123 Main Street, #{'building' * 15}", description: "Project details #{'unbroken' * 30}")
    @unpriced_job = @customer.jobs.create!(name: "Job awaiting an estimate")
    @job.files.attach(io: StringIO.new("Project scope"), filename: "project-scope-#{'long' * 15}.txt", content_type: "text/plain")
    @job.activities.create!(event: "attachment_added", actor: users(:one),
      metadata: { filename: "project-scope-#{'long' * 50}.txt" })
    estimates(:kitchen_estimate).update!(status: "draft")
    @change_order.update!(title: "Additional lighting and electrical improvements")

    visit new_session_path
    fill_in "Email address", with: users(:one).email_address
    fill_in "Password", with: "password"
    click_on "Sign in"
    assert_button "Log out"
  end

  teardown do
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    page.driver.browser.execute_cdp("Emulation.setTouchEmulationEnabled", enabled: false)
  end

  [ 320, 375, 390, 430, 768, 1400 ].each do |width|
    test "core screens fit a #{width}px viewport" do
      set_viewport(width)

      click_on "Menu" if width < 768
      within "nav[aria-label='Main navigation']" do
        click_on "Customers"
      end
      assert_current_path customers_path
      if width < 768
        assert_no_selector "[role=region][aria-label='Customers']"
        within "ul[aria-label='Customers']" do
          assert_selector "li", count: 1
          assert_selector "h2", text: @customer.name
          assert_selector "dt", text: "Contact", exact_text: true
          assert_selector "dd", text: @customer.contact_name
          assert_selector "dt", text: "Email", exact_text: true
          assert_selector "dd", text: @customer.email
          assert_selector "p", text: @customer.address
          assert_link "View #{@customer.name}", href: customer_path(@customer)
          clipped = all("h2, p, dt, dd").filter_map do |element|
            element.text if element.evaluate_script("this.scrollWidth > this.clientWidth")
          end
          assert_empty clipped, "Customer details must wrap within the mobile record"
        end
        assert_layout_fits(width, current_path)
        click_on "View #{@customer.name}"
        assert_current_path customer_path(@customer)
      else
        assert_no_selector "ul[aria-label='Customers']"
        assert_scrollable_table "Customers", width
      end
      click_on "Menu" if width < 768
      within "nav[aria-label='Main navigation']" do
        click_on "Jobs", exact: true
      end
      assert_current_path jobs_path
      fill_in "Search jobs", with: "kitchen"
      if width < 768
        assert_no_selector "[role=region][aria-label='Jobs']"
        within "ul[aria-label='Jobs']" do
          assert_selector "li", count: 1
          assert_selector "h2", text: @job.name
          assert_selector "p", text: @job.address
          assert_selector "dt", text: "Customer", exact_text: true
          assert_selector "dd", text: @customer.name
          assert_selector "span", text: @job.status.humanize, exact_text: true
          assert_link "View #{@job.name}", href: job_path(@job)
          clipped = all("h2, p, dt, dd").filter_map do |element|
            element.text if element.evaluate_script("this.scrollWidth > this.clientWidth")
          end
          assert_empty clipped, "Job details must wrap within the mobile record"
        end
        assert_layout_fits(width, current_path)
      else
        assert_no_selector "ul[aria-label='Jobs']"
        assert_selector "tbody tr", count: 1
        assert_text @job.name
        assert_scrollable_table "Jobs", width
      end

      paths = [
        root_path,
        account_path, account_security_path,
        new_customer_path, edit_customer_path(@customer), customer_path(@customer),
        new_job_path, edit_job_path(@job), job_path(@job),
        new_job_estimate_path(@unpriced_job), job_estimate_path(@job), edit_job_estimate_path(@job),
        job_change_orders_path(@job), job_change_order_path(@job, @change_order),
        new_job_change_order_path(@job), edit_job_change_order_path(@job, @change_order)
      ]
      paths.each do |path|
        visit path
        assert_selector "h1"
        assert_layout_fits(width, path)
      end

      visit job_estimate_path(@job)
      assert_scrollable_table "Estimate line items", width
      visit job_change_orders_path(@job)
      assert_scrollable_table "Change orders", width
      visit job_change_order_path(@job, @change_order)
      assert_scrollable_table "Change order line items", width
    end
  end

  test "job filters and record links work on a narrow mobile viewport" do
    set_viewport(320)
    visit jobs_path
    assert_selector "ul[aria-label='Jobs'] li", count: 2
    [ find("summary", text: "All statuses"), find_link("Reset filters") ].each do |control|
      assert_operator control.evaluate_script("this.getBoundingClientRect().height"), :>=, 44
    end

    fill_in "Search jobs", with: "kitchen"
    assert_selector "ul[aria-label='Jobs'] li", count: 1
    assert_field "Search jobs", with: "kitchen", focused: true
    find("summary", text: "All statuses").click
    check "Draft"
    assert_text "No jobs match your filters"
    assert_layout_fits(320, current_path)
    uncheck "Draft"
    check "In progress"
    assert_selector "ul[aria-label='Jobs'] li", count: 1
    assert_current_path jobs_path, ignore_query: true
    assert_field "Search jobs", with: "kitchen"
    assert_checked_field "In progress", visible: :all
    assert_selector "ul[aria-label='Jobs'] li", text: @job.name, count: 1
    assert_layout_fits(320, current_path)

    click_on "Reset filters"
    assert_current_path jobs_path
    assert_field "Search jobs", with: ""
    assert_no_selector "input[name='status[]']:checked", visible: :all
    assert_selector "ul[aria-label='Jobs'] li", count: 2
    within find("ul[aria-label='Jobs'] li", text: @unpriced_job.name) do
      assert_selector "dd", text: @customer.name
      assert_no_selector "p"
    end
    assert_layout_fits(320, current_path)
    click_on "View #{@job.name}"
    assert_current_path job_path(@job)
    assert_selector "h1", text: @job.name
  end

  test "line items can be added removed and saved on mobile and tablet viewports" do
    [ 320, 768 ].each do |width|
      set_viewport(width)
      job = @customer.jobs.create!(name: "Responsive estimate #{width}")

      [ [ new_job_estimate_path(job), "Create Estimate" ],
        [ new_job_change_order_path(job), "Create Change order" ] ].each do |path, submit|
        visit path
        fill_in "Title", with: "Additional work" if has_field?("Title", wait: 0)
        within "[data-testid=line-item]" do
          fill_line_item("Materials #{width}", quantity: "3", unit_price: "25")
        end
        click_on "Add line item"
        assert_selector "[data-testid=line-item]", count: 2
        within all("[data-testid=line-item]").last do
          fill_line_item("Temporary work", quantity: "2", unit_price: "10")
          scroll_to find_button("Remove"), align: :center
          assert_button "Remove", obscured: false
          click_on "Remove"
        end
        assert_selector "[data-testid=line-item]", count: 1
        assert_layout_fits(width, path)
        click_on submit
        assert_text "successfully created"
        assert_text "Materials #{width}"
        assert_text "$75.00"
        assert_layout_fits(width, current_path)
      end
    end
  end

  test "mobile navigation supports keyboard focus Escape and Turbo restoration" do
    set_viewport(320)
    assert_selector 'button[aria-controls="main-navigation"][aria-expanded="false"]', text: "Menu"
    assert_no_link "Account"
    menu = find_button("Menu")
    menu.send_keys(:enter)
    assert_selector 'button[aria-controls="main-navigation"][aria-expanded="true"]', text: "Menu"
    assert_selector "button:focus", text: "Menu"
    menu.send_keys(:tab)
    assert_selector "nav a:focus", text: "Dashboard"
    find_link("Dashboard", exact: true).send_keys(:tab)
    assert_selector "nav a:focus", text: "Customers"
    find_link("Customers", exact: true).send_keys(:escape)
    assert_selector 'button[aria-controls="main-navigation"][aria-expanded="false"]', text: "Menu"
    assert_selector "button:focus", text: "Menu"
    assert_no_link "Account"

    page.execute_script("window.responsiveNavigationMarker = true")
    [ [ "Customers", customers_path ], [ "Jobs", jobs_path ], [ "Account", account_path ], [ "Dashboard", root_path ] ].each do |label, path|
      click_on "Menu"
      within "nav[aria-label='Main navigation']" do
        click_on label, exact: true
      end
      assert_current_path path
      if label == "Customers"
        page.go_back
        assert_current_path root_path
        assert_selector 'button[aria-controls="main-navigation"][aria-expanded="false"]', text: "Menu"
        page.go_forward
        assert_current_path customers_path
        assert_selector 'button[aria-controls="main-navigation"][aria-expanded="false"]', text: "Menu"
      end
      assert page.evaluate_script("window.responsiveNavigationMarker === true"), "Expected Turbo navigation"
      assert_selector 'button[aria-controls="main-navigation"][aria-expanded="false"]', text: "Menu"
    end
    page.go_back
    assert_current_path account_path
    assert_selector 'button[aria-controls="main-navigation"][aria-expanded="false"]', text: "Menu"
    page.go_forward
    assert_current_path root_path
    assert_selector 'button[aria-controls="main-navigation"][aria-expanded="false"]', text: "Menu"

    click_on "Menu"
    find_button("Menu").send_keys(:tab)
    find_link("Dashboard", exact: true).send_keys(:tab)
    find_link("Customers", exact: true).send_keys(:tab)
    find_link("Jobs", exact: true).send_keys(:tab)
    find_link("Account", exact: true).send_keys(:tab)
    assert_selector "nav button:focus", text: "Log out"
    find_button("Log out").send_keys(:tab)
    assert_selector 'button[aria-controls="main-navigation"][aria-expanded="false"]', text: "Menu"

    click_on "Menu"
    click_on "Log out"
    assert_current_path new_session_path
    assert_no_button "Menu"
    visit jobs_path
    assert_current_path new_session_path
  end

  test "navigation adapts between mobile and desktop without losing focus" do
    set_viewport(375)
    find_button("Menu").send_keys(:enter)
    set_viewport(1400)
    assert_no_button "Menu"
    assert_selector "nav a:focus", text: "Dashboard"
    assert_link "Customers"
    assert_link "Jobs", exact: true
    assert_link "Account"
    assert_button "Log out"
    set_viewport(375)
    assert_selector 'button[aria-controls="main-navigation"][aria-expanded="false"]', text: "Menu"
    assert_selector "button:focus", text: "Menu"
    click_on "Menu"
    assert_link "Account", count: 1
  end

  test "authentication forms and validation fit mobile tablet and desktop viewports" do
    click_on "Log out"
    assert_selector 'meta[name="viewport"]', visible: false, count: 1 do |meta|
      meta["content"].split(",").map(&:strip).sort == [ "initial-scale=1", "width=device-width" ]
    end
    [ 320, 375, 390, 430, 768, 1400 ].each do |width|
      set_viewport(width)
      [ new_session_path, sign_up_path, new_password_path, edit_password_path(users(:one).password_reset_token) ].each do |path|
        visit path
        assert_selector "h1"
        assert_layout_fits(width, path)
      end
      visit sign_up_path
      fill_in "Email address", with: "responsive@example.com"
      fill_in "Password", with: "a long passphrase"
      fill_in "Confirm password", with: "a different passphrase"
      click_on "Create account"
      assert_selector "[role=alert]", text: "Password confirmation doesn't match Password"
      assert_layout_fits(width, current_path)
    end
  end

  test "two-factor setup recovery codes management and challenge fit responsive viewports" do
    visit account_security_path
    assert_all_viewports_fit
    fill_in "Current password", with: "password"
    click_on "Set up two-factor authentication"
    assert_selector "h1", text: "Set up your authenticator"
    find("summary", text: "Can't scan? Enter a setup key").click
    assert_all_viewports_fit
    secret = users(:one).reload.otp_setup_secret
    fill_in "Authenticator code", with: ROTP::TOTP.new(secret).now
    click_on "Enable two-factor authentication"
    assert_selector "h1", text: "Two-factor authentication is enabled"
    recovery_code = find('ul[aria-label="Recovery codes"] li', match: :first).text
    assert_all_viewports_fit
    click_on "Skip for now"
    visit account_security_path
    assert_all_viewports_fit
    click_on "Log out"
    fill_in "Email address", with: users(:one).email_address
    fill_in "Password", with: "password"
    click_on "Sign in"
    assert_selector "h1", text: "Verify your sign-in"
    assert_all_viewports_fit
    fill_in "Authenticator or recovery code", with: recovery_code
    click_on "Verify sign-in"
    assert_button "Log out"
  end

  test "job dates save and validation fits at a narrow viewport" do
    set_viewport(320)
    visit new_job_path
    click_on "Create Job"
    assert_text "Name can't be blank"
    assert_layout_fits(320, current_path)
    fill_in "Name", with: "Mobile job"
    find_field("Start date").set(Date.new(2026, 10, 29))
    find_field("Estimated completion (optional)").set(Date.new(2026, 11, 15))
    assert_no_field "Completed at"
    click_on "Create Job"
    assert_text "Job was successfully created."
    job = @customer.jobs.find_by!(name: "Mobile job")
    assert_equal Date.new(2026, 10, 29), job.start_date
    assert_equal Date.new(2026, 11, 15), job.estimated_completion_date
    assert_nil job.completed_at
    assert_layout_fits(320, current_path)
    click_on "Edit job"
    assert_no_field "Completed at"
    assert_field "Estimated completion (optional)", with: "2026-11-15"
    assert_layout_fits(320, current_path)
    find_field("Estimated completion (optional)").set(Date.new(2026, 11, 16))
    click_on "Update Job"
    assert_text "Job was successfully updated."
    assert_equal Date.new(2026, 11, 16), job.reload.estimated_completion_date
  end

  private
    def assert_all_viewports_fit
      [ 320, 375, 390, 430, 768, 1400 ].each do |width|
        set_viewport(width)
        assert_layout_fits(width, current_path)
      end
    end

    def fill_line_item(description, quantity:, unit_price:)
      { "Description" => description, "Quantity" => quantity, "Unit price" => unit_price }.each do |label, value|
        field = find_field(label)
        scroll_to field, align: :center
        field.set(value)
        assert_field label, with: value
      end
    end

    def set_viewport(width)
      # Chrome's outer window has a minimum width; emulate the exact CSS viewport.
      page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
        width: width, height: 1000, deviceScaleFactor: 1, mobile: width <= 768)
      page.driver.browser.execute_cdp("Emulation.setTouchEmulationEnabled", enabled: width <= 768)
      assert_equal width, page.evaluate_script("window.innerWidth")
    end

    def assert_layout_fits(width, path)
      small_fields = page.evaluate_script(<<~JS)
        Array.from(document.querySelectorAll('main input:not([type=hidden]):not([type=submit]), main select, main textarea')).filter(element => {
          if (!element.getClientRects().length) return false;
          const rect = element.getBoundingClientRect();
          const parent = element.parentElement.getBoundingClientRect();
          return rect.left < parent.left - 1 || rect.right > parent.right + 1 || (element.matches('[type=date], [type=datetime-local]') && element.scrollWidth > element.clientWidth) ||
            (!element.matches('[type=checkbox]') && (window.innerWidth < 640 || matchMedia('(any-pointer: coarse)').matches) && parseFloat(getComputedStyle(element).fontSize) < 16);
        }).map(element => element.name)
      JS
      assert_empty small_fields, "Fields overflow their container or invite focus zoom on #{path}: #{small_fields.inspect}"

      clipped_submits = page.evaluate_script(<<~JS)
        Array.from(document.querySelectorAll('main input[type=submit]')).filter(element => {
          const context = document.createElement('canvas').getContext('2d');
          if (!element.getClientRects().length) return false;
          const style = getComputedStyle(element);
          context.font = style.font;
          return context.measureText(element.value).width > element.clientWidth - parseFloat(style.paddingLeft) - parseFloat(style.paddingRight) + 1;
        }).map(element => element.value)
      JS
      assert_empty clipped_submits, "Clipped submit labels on #{path}: #{clipped_submits.inspect}"

      wrapped_badges = page.evaluate_script(<<~JS)
        Array.from(document.querySelectorAll('main span.rounded-full')).filter(element => {
          const range = document.createRange();
          range.selectNodeContents(element);
          return range.getClientRects().length > 1 || element.scrollWidth > element.clientWidth;
        }).map(element => element.textContent.trim())
      JS
      assert_empty wrapped_badges, "Wrapped or overflowing badges on #{path}: #{wrapped_badges.inspect}"

      assert_equal width, page.evaluate_script("window.innerWidth"), "Layout viewport expanded on #{path}"
      assert_equal 1, page.evaluate_script("window.visualViewport.scale"), "Unexpected initial scale on #{path}"
      assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, width,
        "Page overflow at #{width}px on #{path}"

      outside = page.evaluate_script(<<~JS)
        Array.from(document.querySelectorAll('nav a, nav button, main input:not([type=hidden]), main select, main textarea, main button, main a')).filter(element => {
          if (!element.getClientRects().length || element.closest('[role=region]')) return false;
          const target = element.matches('input[type=checkbox]') ? element.labels[0] : element;
          if (!target?.checkVisibility({ checkVisibilityCSS: true })) return false;
          const rect = target.getBoundingClientRect();
          return rect.left < 0 || rect.right > window.innerWidth + 1 || rect.width < 24 || rect.height < 24;
        }).map(element => element.textContent.trim() || element.name)
      JS
      assert_empty outside, "Controls outside viewport or too small on #{path}: #{outside.inspect}"
    end

    def assert_scrollable_table(label, width)
      region = find("[role=region][aria-label='#{label}']")
      assert_layout_fits(width, current_path)
      if width < 768
        assert_operator region.evaluate_script("this.scrollWidth"), :>, region.evaluate_script("this.clientWidth")
      elsif width == 1400
        assert_equal region.evaluate_script("this.clientWidth"), region.evaluate_script("this.scrollWidth")
      end
      if region.evaluate_script("this.scrollWidth > this.clientWidth")
        region.send_keys(:right)
        assert_selector "[role=region][aria-label='#{label}']" do |element|
          element.evaluate_script("this.scrollLeft > 0")
        end
      end
    end
end
