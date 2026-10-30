require "application_system_test_case"

class ActivityTimelineTest < ApplicationSystemTestCase
  test "business snapshots and long generic details fit mobile tablet and desktop layouts" do
    job = jobs(:kitchen_renovation)
    user = users(:one)
    user.update!(email_address: "#{'contractor' * 15}@example.com")
    job.activities.create!(event: "site_visit_scheduled", metadata: {
      instructions: "Use side entrance. #{'unbroken' * 50}", details: { confirmed: true, notes: "First line\nSecond line" }
    })
    job.activities.create!(event: "attachment_added", actor: user,
      metadata: { filename: "project-#{'scope' * 35}.pdf", attachment_id: 123 })
    job.activities.create!(event: "change_order_status_changed", actor: user, metadata: {
      title: "Additional lighting and electrical improvements #{'long' * 50}",
      previous_status: "pending", new_status: "approved", total: "444.00", line_item_count: 2
    })
    job.activities.create!(event: "estimate_status_changed", actor: user, metadata: {
      previous_status: "draft", new_status: "sent", total: "27000.00", line_item_count: 3
    })

    visit new_session_path
    fill_in "Email address", with: user.email_address
    fill_in "Password", with: "password"
    click_on "Sign in"
    assert_button "Log out"

    [ 320, 768, 1400 ].each do |width|
      page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
        width: width, height: 1000, deviceScaleFactor: 1, mobile: width == 320)
      visit job_path(job)
      within "section[aria-labelledby='activity-heading']" do
        assert_selector "li", count: 4
        assert_selector "p", text: "Estimate changed from Draft to Sent"
        assert_selector "dd", text: "$27,000.00"
        assert_selector "dd", text: "3 line items"
        assert_selector "p", text: "Actor unavailable"
        assert_no_selector "dt", text: "Attachment id"
        all("p, dt, dd, time").each do |element|
          assert_operator element.evaluate_script("this.scrollWidth"), :<=, element.evaluate_script("this.clientWidth"), element.text
        end
        all("li").each do |entry|
          header = entry.find("div", match: :first)
          description, actor = header.all("p").map { |element| element.evaluate_script("this.getBoundingClientRect().toJSON()") }
          timestamp = header.find("time").evaluate_script("this.getBoundingClientRect().toJSON()")
          if width >= 768
            assert_in_delta description["top"], timestamp["top"], 1
            assert_operator timestamp["left"], :>=, description["right"]
            assert_in_delta header.evaluate_script("this.getBoundingClientRect().right"), timestamp["right"], 1
          else
            assert_operator timestamp["top"], :>=, actor["bottom"]
          end
        end
        scroll_to find("#activity-heading"), align: :top
        page.save_screenshot(Rails.root.join("tmp/screenshots/activity-#{width}.png"))
      end
      assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, width
    end
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end
end
