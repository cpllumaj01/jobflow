require "application_system_test_case"

class JobFiltersTest < ApplicationSystemTestCase
  setup do
    @customer = customers(:johnson)
    @draft = @customer.jobs.create!(name: "Kitchen draft", status: "draft")
    @quoted = @customer.jobs.create!(name: "Kitchen quoted", status: "quoted")
    @completed = @customer.jobs.create!(name: "Kitchen completed", status: "completed")

    visit new_session_path
    fill_in "Email address", with: users(:one).email_address
    fill_in "Password", with: "password"
    click_on "Sign in"
    assert_button "Log out"
  end

  test "statuses update automatically preserve search and clear to all statuses" do
    visit jobs_path(q: "Kitchen")
    assert_selector "tbody tr", count: 4
    assert_no_button "Filter jobs"
    assert_no_link "Clear selections"
    assert_no_selector "input[name='status[]']:checked", visible: :all
    page.execute_script("window.filterForm = document.querySelector('form[data-controller=job-filters]')")

    find("summary").click
    assert_no_link "Clear selections"
    check "Draft"
    assert_selector "tbody tr", count: 1
    assert_current_path jobs_path(q: "Kitchen", status: [ "draft" ])
    assert_checked_field "Draft", focused: true
    assert_selector "[data-job-filters-target='selection']", text: "Draft", exact_text: true

    # Space toggles the next status through native keyboard interaction.
    find_field("Quoted").send_keys(:space)
    assert_selector "tbody tr", count: 2
    assert_current_path jobs_path(q: "Kitchen", status: [ "draft", "quoted" ])
    assert_checked_field "Quoted", focused: true
    assert_selector "summary", text: "2 statuses selected"
    assert_selector "details[open]"
    assert_field "Search jobs", with: "Kitchen"

    fill_in "Search jobs", with: "Kitchen quoted"
    assert_selector "tbody tr", count: 1
    assert_selector "tbody tr", text: @quoted.name
    assert_field "Search jobs", with: "Kitchen quoted", focused: true
    assert_checked_field "Draft", visible: :all
    assert_checked_field "Quoted", visible: :all

    find("summary").click
    uncheck "Quoted"
    assert_text "No jobs match your filters"
    uncheck "Draft"
    assert_selector "tbody tr", count: 1
    assert_selector "tbody tr", text: @quoted.name
    assert_no_selector "input[name='status[]']:checked", visible: :all
    assert_selector "details[open]"
    assert_unchecked_field "Draft", focused: true
    assert_selector "[data-job-filters-target='selection']", text: "All statuses"
    assert_current_path jobs_path(q: "Kitchen quoted")
    assert page.evaluate_script("window.filterForm === document.querySelector('form[data-controller=job-filters]')")

    click_on "Reset filters"
    assert_current_path jobs_path
    assert_field "Search jobs", with: ""
    assert_selector "tbody tr", count: 4
  end

  test "dropdown supports keyboard dismissal outside clicks and focus leaving the filter" do
    visit jobs_path
    summary = find("summary", text: "All statuses")
    summary.send_keys(:enter)
    assert_selector "details[open]"
    summary.send_keys(:tab)
    assert_field "Draft", focused: true
    find_field("Draft").send_keys(:space)
    assert_current_path jobs_path(q: "", status: [ "draft" ])
    assert_checked_field "Draft", focused: true
    assert_selector "summary", text: "Draft"
    find_field("Draft").send_keys(:tab)
    assert_field "Quoted", focused: true
    find_field("Quoted").send_keys(:space)
    assert_selector "summary", text: "2 statuses selected"
    assert_selector "details[open]"
    find_field("Quoted").send_keys(:escape)
    assert_no_selector "details[open]"
    assert_selector "summary:focus", text: "2 statuses selected"

    find("summary").send_keys(:space)
    assert_checked_field "Draft"
    assert_checked_field "Quoted"
    find_field("Search jobs").click
    assert_no_selector "details[open]"
    assert_field "Search jobs", focused: true

    find("summary").click
    find("h1").click
    assert_no_selector "details[open]"
    find("summary").click
    find_field("Cancelled").send_keys(:tab)
    assert_no_selector "details[open]"
    assert_selector "a:focus", text: "Reset filters"
  end

  test "status changes include pending search and cancel its delayed submission" do
    visit jobs_path
    page.execute_script(<<~JS)
      window.filterSubmissions = 0
      const form = document.querySelector('form[data-controller=job-filters]')
      form.dataset.jobFiltersDebounceDelayValue = '1000'
      form.addEventListener('turbo:submit-start', () => window.filterSubmissions++)
    JS
    fill_in "Search jobs", with: "Kitchen quoted"
    find("summary").click
    check "Quoted"
    assert_current_path jobs_path(q: "Kitchen quoted", status: [ "quoted" ])
    assert_selector "tbody tr", count: 1
    assert_selector "tbody tr", text: @quoted.name
    assert_no_selector "turbo-frame[busy]"
    assert_equal 1, page.evaluate_script("window.filterSubmissions")
    click_on "Reset filters"
    assert_current_path jobs_path
    assert_field "Search jobs", with: ""
  end

  test "unknown legacy statuses stay selected through search until explicitly cleared" do
    visit jobs_path(status: "unknown")
    find("summary").click
    assert_text "No jobs match your filters"
    assert_checked_field "Unknown status: unknown", visible: :all
    fill_in "Search jobs", with: "Kitchen"
    assert_current_path jobs_path(q: "Kitchen", status: [ "unknown" ])
    assert_text "No jobs match your filters"
    assert_checked_field "Unknown status: unknown", visible: :all
    click_on "Reset filters"
    assert_selector "tbody tr", count: 4
    assert_current_path jobs_path
    assert_field "Search jobs", with: ""
    assert_no_selector "input[name='status[]']:checked", visible: :all
  end

  test "filters support native submission and pagination with JavaScript disabled" do
    25.times { |index| @customer.jobs.create!(name: "Kitchen draft #{index}", status: "draft") }
    page.driver.browser.execute_cdp("Emulation.setScriptExecutionDisabled", value: true)
    visit jobs_path
    assert_button "Filter jobs"
    assert_no_link "Clear selections"
    fill_in "Search jobs", with: "Kitchen"
    find("summary").click
    check "Draft"
    check "Quoted"
    click_on "Filter jobs"
    assert_text "Showing 1–25 of 27"
    assert_checked_field "Draft", visible: :all
    assert_checked_field "Quoted", visible: :all
    click_on "Next"
    assert_text "Showing 26–27 of 27"
    assert_field "Search jobs", with: "Kitchen"
    assert_checked_field "Draft", visible: :all
    assert_checked_field "Quoted", visible: :all
    find("summary").click
    uncheck "Draft"
    click_on "Filter jobs"
    assert_current_path jobs_path, ignore_query: true do |url|
      Rack::Utils.parse_nested_query(url.query).except("commit") == { "q" => "Kitchen", "status" => [ "quoted" ] }
    end
    assert_selector "tbody tr", count: 1
    assert_selector "tbody tr", text: @quoted.name
    find("summary").click
    uncheck "Quoted"
    click_on "Filter jobs"
    assert_current_path jobs_path, ignore_query: true do |url|
      Rack::Utils.parse_nested_query(url.query).except("commit") == { "q" => "Kitchen" }
    end
    assert_text "Showing 1–25 of 29"
    assert_no_selector "input[name='status[]']:checked", visible: :all

    click_on "Reset filters"
    assert_current_path jobs_path
    assert_field "Search jobs", with: ""
  ensure
    page.driver.browser.execute_cdp("Emulation.setScriptExecutionDisabled", value: false)
  end

  test "status labels and controls fit phone and desktop viewports" do
    [ 320, 375, 390, 430, 1400 ].each do |width|
      page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
        width: width, height: 667, deviceScaleFactor: 1, mobile: width < 500)
      visit jobs_path(q: "Kitchen", status: [ "draft", "quoted" ])
      assert_selector "summary", text: "2 statuses selected"
      assert_selector "[data-job-filters-target='selection']" do |label|
        label.evaluate_script("this.scrollWidth <= this.clientWidth")
      end
      find("summary").click
      assert_checked_field "Draft"
      assert_checked_field "Quoted"
      assert_selector "[data-job-filters-target='panel']" do |panel|
        rect = panel.evaluate_script("this.getBoundingClientRect().toJSON()")
        rect["top"] >= 0 && rect["bottom"] <= 667 && rect["left"] >= 0 && rect["right"] <= width
      end
      assert_no_button "Filter jobs"
      assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, width

      within "form[data-controller='job-filters']" do
        all("summary, fieldset label, a, input[type=search]").each do |control|
          rect = control.evaluate_script("this.getBoundingClientRect().toJSON()")
          assert_operator rect["left"], :>=, 0
          assert_operator rect["right"], :<=, width
          assert_operator rect["height"], :>=, 44
        end
      end
      uncheck "Draft"
      assert_text @quoted.name
      assert_no_text @draft.name
      assert_field "Search jobs", with: "Kitchen"
    end
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end
end
