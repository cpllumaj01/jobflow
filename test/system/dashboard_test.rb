require "application_system_test_case"

class DashboardTest < ApplicationSystemTestCase
  setup do
    visit new_session_path
    fill_in "Email address", with: users(:one).email_address
    fill_in "Password", with: "password"
    click_on "Sign in"
    assert_selector "h1", text: "Dashboard"
  end

  teardown do
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    page.driver.browser.execute_cdp("Emulation.setScriptExecutionDisabled", value: false)
  end

  test "dashboard drill downs support keyboard navigation without JavaScript" do
    approved = customers(:johnson).jobs.create!(name: "Approved addition", status: "approved")
    completed = customers(:johnson).jobs.create!(name: "Completed addition", status: "completed")
    jobs(:office_buildout).update!(status: "approved")
    page.driver.browser.execute_cdp("Emulation.setScriptExecutionDisabled", value: true)
    visit root_path

    active_link = find("main a", text: "View active jobs")
    active_link.send_keys(:tab, [ :shift, :tab ])
    assert_selector "main a:focus", text: "Active jobs"
    assert_operator active_link.evaluate_script("parseFloat(getComputedStyle(this).outlineWidth)"), :>=, 2
    active_link.send_keys(:enter)
    assert_current_path jobs_path(status: %w[approved in_progress])
    assert_selector "tbody tr", count: 2
    assert_selector "tbody tr", text: approved.name
    assert_selector "tbody tr", text: jobs(:kitchen_renovation).name
    assert_no_selector "tbody tr", text: completed.name
    assert_no_selector "tbody tr", text: jobs(:office_buildout).name
    assert_checked_field "Approved", visible: :all
    assert_checked_field "In progress", visible: :all

    visit root_path
    find_link("Completed: 1 job").send_keys(:enter)
    assert_current_path jobs_path(status: [ "completed" ])
    assert_selector "tbody tr", count: 1
    assert_selector "tbody tr", text: completed.name

    visit root_path
    find("main a", text: "View customers").click
    assert_current_path customers_path
    assert_selector "tbody tr", count: 1
    assert_selector "tbody tr", text: customers(:johnson).name

    visit root_path
    find("main a", text: "View all jobs").click
    assert_current_path jobs_path
    assert_selector "tbody tr", count: 3
  end

  test "dashboard charts and large currency values fit mobile tablet and desktop" do
    if ENV["DASHBOARD_SCREENSHOTS"]
      [ 375, 1400 ].each do |width|
        set_viewport(width)
        visit root_path
        assert_selector "#pending_estimates dd", text: "0", exact_text: true
        assert_selector "#pending_change_orders dd", text: "0", exact_text: true
        assert_selector "#total_current_contract_value dd", text: "$27,000.00", exact_text: true
        save_dashboard_screenshot("normal-#{width}")
      end
    end
    # Uneven distribution and a large real value exercise both visualizations.
    30.times { |index| customers(:johnson).jobs.create!(name: "Upcoming work #{index}", status: "draft") }
    estimate_line_items(:cabinets).update!(unit_price: "1234567890.12")
    change_orders(:kitchen_lighting).update!(status: "approved")
    pending_job = customers(:johnson).jobs.create!(name: "Awaiting decision", status: "quoted")
    pending_job.create_estimate!(status: "sent")
    pending_job.change_orders.create!(title: "Extra work", status: "pending")

    [ 320, 375, 390, 430, 768, 1024, 1400 ].each do |width|
      set_viewport(width)
      visit root_path
      assert_selector "#total_jobs dd", text: "32", exact_text: true
      assert_selector "#total_current_contract_value dd", text: "$1,234,583,334.12", exact_text: true
      assert_selector "#pending_estimates dd", text: "1", exact_text: true
      assert_selector "#pending_change_orders dd", text: "1", exact_text: true
      assert_link "Draft: 30 jobs"
      assert_selector "#contract_breakdown", text: "Approved change orders"
      assert_layout_fits(width)
      save_dashboard_screenshot(width)
    end
  end

  test "onboarding and zero financial states fit small and large screens" do
    jobs(:kitchen_renovation).destroy!
    [ 320, 768, 1400 ].each do |width|
      set_viewport(width)
      visit root_path
      assert_link "Create first job", href: new_job_path
      assert_no_selector "#jobs_by_status, #contract_breakdown"
      assert_layout_fits(width)
      save_dashboard_screenshot("no-jobs-#{width}")
    end
    customers(:johnson).destroy!
    [ 320, 1400 ].each do |width|
      set_viewport(width)
      visit root_path
      assert_link "Add first customer", href: new_customer_path
      assert_layout_fits(width)
      save_dashboard_screenshot("new-account-#{width}")
    end
    click_on "Add first customer"
    assert_current_path new_customer_path

    customer = users(:one).customers.create!(name: "New customer")
    customer.jobs.create!(name: "First job")
    [ 320, 1400 ].each do |width|
      set_viewport(width)
      visit root_path
      assert_text "No approved contract value yet"
      assert_link "Draft: 1 job"
      assert_no_selector "#contract_breakdown"
      assert_layout_fits(width)
      save_dashboard_screenshot("unpriced-#{width}")
    end
  end

  private
    def save_dashboard_screenshot(name)
      return unless ENV["DASHBOARD_SCREENSHOTS"]

      browser = page.driver.browser
      size = browser.execute_cdp("Page.getLayoutMetrics").fetch("cssContentSize")
      screenshot = browser.execute_cdp("Page.captureScreenshot", captureBeyondViewport: true,
        clip: { x: 0, y: 0, width: size.fetch("width"), height: size.fetch("height"), scale: 1 })
      FileUtils.mkdir_p(Rails.root.join("tmp/screenshots"))
      File.binwrite(Rails.root.join("tmp/screenshots/dashboard-#{name}.png"), Base64.decode64(screenshot.fetch("data")))
    end

    def set_viewport(width)
      page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
        width: width, height: 1000, deviceScaleFactor: 1, mobile: width < 768)
    end

    def assert_layout_fits(width)
      assert_equal width, page.evaluate_script("window.innerWidth")
      assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, width
      clipped = page.evaluate_script(<<~JS)
        Array.from(document.querySelectorAll('main h1, main h2, main h3, main dt, main dd, main a')).filter(element => {
          const rect = element.getBoundingClientRect();
          return element.scrollWidth > element.clientWidth + 1 || rect.left < 0 || rect.right > window.innerWidth;
        }).map(element => element.textContent.trim())
      JS
      assert_empty clipped, "Clipped dashboard content at #{width}px: #{clipped.inspect}"
      # Currency totals should remain on a single line at realistic large values.
      total = find("#total_current_contract_value dd")
      assert_operator total.evaluate_script("this.clientHeight"), :<=, total.evaluate_script("parseFloat(getComputedStyle(this).lineHeight)") + 1
      all("main a").each do |link|
        assert_operator link.evaluate_script("this.getBoundingClientRect().height"), :>=, 44
      end
      assert_selector "h1", count: 1
      assert_selector "section[aria-labelledby='contract-title']"
      assert_selector "section[aria-labelledby='approvals-title']"
    end
end
