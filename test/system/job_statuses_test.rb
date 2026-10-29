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
      within "section[aria-labelledby='job-status-heading']" do
        select "Quoted", from: "New status"
        click_on "Update status"
      end
      assert_text "Job status was successfully updated."
      assert_current_path job_path(@job)
      assert_equal "quoted", @job.reload.status
      assert_nil @job.completed_at
      assert_no_selector "dt", text: "Completed", exact_text: true
      assert_fits(width)

      click_on "Complete job"
      assert_select "New status", selected: "Completed"
      assert_selector "dt", text: "Completed", exact_text: true
      assert_no_button "Complete job"
      completion = @job.reload.completed_at
      assert_not_nil completion
      assert_equal "draft", @job.estimate.reload.status
      assert_fits(width)

      within "section[aria-labelledby='job-status-heading']" do
        select "In progress", from: "New status"
        find_button("Update status").send_keys(:enter)
      end
      assert_no_selector "dt", text: "Completed", exact_text: true
      assert_equal "in_progress", @job.reload.status
      assert_nil @job.completed_at
      within "section[aria-labelledby='activity-heading']" do
        assert_selector "dt", text: "Previous completed at", exact_text: true
        assert_selector "dd", text: completion.iso8601(6), count: 2
      end
      click_on "Complete job"
      assert_select "New status", selected: "Completed"
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

  private
    def assert_fits(width)
      assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, width
      within "section[aria-labelledby='job-status-heading']" do
        all("select, input[type=submit], button").each do |control|
          rect = control.evaluate_script("this.getBoundingClientRect().toJSON()")
          assert_operator rect["left"], :>=, 0
          assert_operator rect["right"], :<=, width
          assert_operator rect["height"], :>=, 44
        end
      end
    end
end
