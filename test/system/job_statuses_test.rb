require "application_system_test_case"

class JobStatusesTest < ApplicationSystemTestCase
  setup do
    @job = jobs(:kitchen_renovation)
    @job.estimate.update!(status: "draft")
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

  [ 320, 1400 ].each do |width|
    test "status completion reopening and scheduling work at #{width}px" do
      page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
        width: width, height: 1000, deviceScaleFactor: 1, mobile: width == 320)
      page.driver.browser.execute_cdp("Emulation.setTouchEmulationEnabled", enabled: width == 320)
      visit job_path(@job)
      open_statuses
      click_on "Quoted"
      assert_text "Job status was successfully updated."
      assert_current_path job_path(@job)
      assert_equal "quoted", @job.reload.status
      assert_nil @job.completed_at
      assert_no_selector "dt", text: "Completed", exact_text: true
      assert_fits(width)

      click_on "Complete job"
      assert_status "completed"
      assert_selector "dt", text: "Completed", exact_text: true
      assert_no_button "Complete job"
      completion = @job.reload.completed_at
      assert_not_nil completion
      assert_equal "draft", @job.estimate.reload.status
      assert_fits(width)

      open_statuses
      find("summary", text: "In progress", exact_text: true).send_keys(:enter)
      assert_equal "completed", @job.reload.status
      find_button("Reopen job").send_keys(:enter)
      assert_no_selector "dt", text: "Completed", exact_text: true
      assert_equal "in_progress", @job.reload.status
      assert_nil @job.completed_at
      within "section[aria-labelledby='activity-heading']" do
        assert_selector "dt", text: "Previous completed at", exact_text: true
        assert_selector "dd", text: completion.in_time_zone.strftime("%b %-d, %Y at %-I:%M %p %Z"), count: 2
      end
      click_on "Complete job"
      assert_status "completed"
      assert_selector "dt", text: "Completed", exact_text: true
      new_completion = @job.reload.completed_at
      assert_operator new_completion, :>, completion
      assert_equal 4, @job.activities.count
      assert_fits(width)

      click_on "Edit job"
      assert_no_field "Completed at"
      assert_field "Estimated completion (optional)", with: "2026-11-15"
      find_field("Estimated completion (optional)").set(Date.new(2026, 12, 1))
      click_on "Update Job"
      assert_text "Job was successfully updated."
      assert_equal Date.new(2026, 12, 1), @job.reload.estimated_completion_date
      assert_equal new_completion, @job.completed_at
      assert_equal 4, @job.activities.count

      visit new_job_path
      assert_no_field "Completed at"
      fill_in "Name", with: "Completed job #{width}"
      select "Completed", from: "Status"
      click_on "Create Job"
      assert_text "Job was successfully created."
      created = customers(:johnson).jobs.find_by!(name: "Completed job #{width}")
      assert_not_nil created.completed_at
      assert_nil created.estimated_completion_date
      assert_selector "dt", text: "Completed", exact_text: true
      assert_fits(width)
    end
  end

  test "every status is available and only consequential transitions need confirmation" do
    visit job_path(@job)
    %w[draft quoted approved in_progress cancelled completed].each do |status|
      open_statuses
      if status == "cancelled"
        find("summary", text: "Cancelled", exact_text: true).click
        assert_equal "in_progress", @job.reload.status
        assert_status "in_progress"
        click_on "Cancel job"
      else
        click_on status.humanize
      end
      assert_status status
      assert_equal status, @job.reload.status
    end
    assert_equal 6, @job.activities.count
  end

  test "dropdown supports keyboard navigation Escape outside clicks and leaving focus" do
    visit job_path(@job)
    toggle = find("summary", text: "Change status")
    toggle.send_keys(:enter)
    assert_selector "details[data-controller='status-dropdown'][open]"
    toggle.send_keys(:tab)
    assert_button "Draft", focused: true
    find_button("Draft").send_keys(:tab)
    assert_button "Quoted", focused: true
    find_button("Quoted").send_keys(:enter)
    assert_status "quoted"
    assert_equal "quoted", @job.reload.status

    open_statuses
    find_button("Draft").send_keys(:escape)
    assert_no_selector "details[data-controller='status-dropdown'][open]"
    assert_selector "summary:focus", text: "Change status"
    find("summary", text: "Change status").send_keys(:space)
    find("h1").click
    assert_no_selector "details[data-controller='status-dropdown'][open]"

    open_statuses
    find("summary", text: "Cancelled", exact_text: true).send_keys(:tab)
    assert_no_selector "details[data-controller='status-dropdown'][open]"
    assert_link @job.customer.name, focused: true
    assert_equal "quoted", @job.reload.status
  end

  test "confirmation can be dismissed without changing saved status" do
    @job.update!(status: "completed")
    visit job_path(@job)
    open_statuses
    find("summary", text: "In progress", exact_text: true).send_keys(:enter)
    assert_text "Reopen as in progress?"
    find_button("Reopen job").send_keys(:escape)
    assert_no_selector "details[data-controller='status-dropdown'][open]"
    assert_selector "summary:focus", text: "Change status"
    assert_status "completed"
    assert_equal "completed", @job.reload.status
    assert_no_difference("Activity.count") do
      open_statuses
      find("h1").click
    end
  end

  [ 320, 1400 ].each do |width|
    test "native status actions and confirmations work with JavaScript disabled at #{width}px" do
      page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
        width: width, height: 1000, deviceScaleFactor: 1, mobile: width == 320)
      page.driver.browser.execute_cdp("Emulation.setScriptExecutionDisabled", value: true)
      visit job_path(@job)
      open_statuses
      find_button("Quoted").send_keys(:enter)
      assert_status "quoted"
      click_on "Complete job"
      assert_status "completed"
      completion = @job.reload.completed_at
      open_statuses
      find("summary", text: "Approved", exact_text: true).send_keys(:enter)
      find_button("Reopen job").send_keys(:enter)
      assert_status "approved"
      assert_nil @job.reload.completed_at
      open_statuses
      find("summary", text: "Cancelled", exact_text: true).click
      click_on "Cancel job"
      assert_status "cancelled"
      assert_equal "cancelled", @job.reload.status
      assert_equal completion.iso8601(6), @job.activities.find_by!("metadata ->> 'previous_status' = ?", "completed").metadata["previous_completed_at"]
      assert_equal 4, @job.activities.count
    ensure
      page.driver.browser.execute_cdp("Emulation.setScriptExecutionDisabled", value: false)
    end
  end

  test "a rejected status submission keeps the completed badge and saved choice" do
    @job.update!(status: "completed")
    completion = @job.completed_at
    visit job_path(@job)
    open_statuses
    find("summary", text: "In progress", exact_text: true).click
    within find_button("Reopen job").find(:xpath, "..") do
      find("input[name='job[status]']", visible: :all).execute_script("this.value = 'unknown'")
      click_on "Reopen job"
    end
    assert_text "Status is not included in the list"
    assert_status "completed"
    assert_equal "completed", @job.reload.status
    assert_equal completion, @job.completed_at
    assert_empty @job.activities
    open_statuses
    assert_button "Completed Current", disabled: true
  end

  test "header and expanded status choices fit phone tablet and desktop widths" do
    @job.update!(name: "Kitchen renovation with custom cabinetry and a very long job title", status: "completed")
    @job.customer.update!(name: "Johnson family residence and property management")
    [ 320, 375, 390, 430, 768, 1400 ].each do |width|
      page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
        width: width, height: 800, deviceScaleFactor: 1, mobile: width < 500)
      page.driver.browser.execute_cdp("Emulation.setTouchEmulationEnabled", enabled: width < 500)
      %w[completed in_progress].each do |status|
        @job.update!(status: status)
        visit job_path(@job)
        assert_status status
        assert_fits(width)
        open_statuses
        find("summary", text: status == "completed" ? "In progress" : "Cancelled", exact_text: true).click
        assert_button status == "completed" ? "Reopen job" : "Cancel job"
        assert_selector "[data-status-dropdown-target='panel']" do |panel|
          rect = panel.evaluate_script("this.getBoundingClientRect().toJSON()")
          rect["left"] >= 0 && rect["right"] <= width && rect["top"] >= 0 && rect["bottom"] <= 800
        end
        assert_fits(width)
        panel_rect = find("[data-status-dropdown-target='panel']").evaluate_script("this.getBoundingClientRect().toJSON()")
        within "#job-header" do
          all("a[href$='/edit'], button", text: /Edit job|Complete job/).each do |action|
            rect = action.evaluate_script("this.getBoundingClientRect().toJSON()")
            assert panel_rect["right"] <= rect["left"] || panel_rect["left"] >= rect["right"] ||
              panel_rect["bottom"] <= rect["top"] || panel_rect["top"] >= rect["bottom"], "Dropdown covers #{action.text} at #{width}px"
          end
        end
      end
    end
  end

  private
    def open_statuses
      find("summary", text: "Change status", exact_text: true).click
      assert_selector "details[data-controller='status-dropdown'][open]"
    end

    def assert_status(status)
      assert_selector "#job-status", text: status.humanize, exact_text: true
      assert_selector "button[aria-current='true'][disabled]", text: status.humanize, visible: :all, count: 1
    end

    def assert_fits(width)
      assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, width
      within "#job-header" do
        all("summary, button:not([disabled]), a[href$='/edit']").each do |control|
          rect = control.evaluate_script("this.getBoundingClientRect().toJSON()")
          assert_operator rect["left"], :>=, 0
          assert_operator rect["right"], :<=, width
          assert_operator rect["height"], :>=, 44
        end
      end
    end
end
