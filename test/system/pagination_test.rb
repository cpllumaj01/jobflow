require "application_system_test_case"

class PaginationTest < ApplicationSystemTestCase
  setup do
    @customer = customers(:johnson)

    visit new_session_path
    fill_in "Email address", with: users(:one).email_address
    fill_in "Password", with: "password"
    click_on "Sign in"
    assert_button "Log out"
  end

  test "job pagination updates the frame and supports browser history with filters intact" do
    timestamp = Time.current
    added_jobs = Array.new(51) do |index|
      @customer.jobs.create!(name: "Paged job #{index}", status: "draft", created_at: timestamp)
    end
    visit jobs_path(q: "Paged", status: "draft")
    assert_text "Page 1 of 3"
    assert_list_records added_jobs.reverse.first(25)
    page.execute_script("window.paginationSearchField = document.querySelector('input[name=q]')")

    within "nav[aria-label='Pagination']" do
      click_on "Next"
    end
    assert_text "Showing 26–50 of 51"
    assert_current_path jobs_path(q: "Paged", status: "draft", page: 2)
    assert_list_records added_jobs.reverse.slice(25, 25)
    assert page.evaluate_script("window.paginationSearchField === document.querySelector('input[name=q]')")
    assert_no_selector "html[aria-busy], turbo-frame[busy]"

    within "nav[aria-label='Pagination']" do
      click_on "Next"
    end
    assert_text "Showing 51–51 of 51"
    assert_current_path jobs_path(q: "Paged", status: "draft", page: 3)
    assert_list_records [ added_jobs.first ]
    assert_no_selector "html[aria-busy], turbo-frame[busy]"
    page.go_back
    assert_text "Showing 26–50 of 51"
    assert_current_path jobs_path(q: "Paged", status: "draft", page: 2)
    assert_list_records added_jobs.reverse.slice(25, 25)
    assert_no_selector "html[aria-busy], turbo-frame[busy]"
    page.go_back
    assert_current_path jobs_path(q: "Paged", status: "draft")
    assert_text "Showing 1–25 of 51"
    assert_list_records added_jobs.reverse.first(25)
    assert_field "Search jobs", with: "Paged"
    assert_select "Status", selected: "Draft"
    page.go_forward
    assert_text "Showing 26–50 of 51"
    assert_current_path jobs_path(q: "Paged", status: "draft", page: 2)
    assert_list_records added_jobs.reverse.slice(25, 25)
    assert_field "Search jobs", with: "Paged"
    assert_select "Status", selected: "Draft"

    within "tbody tr", text: added_jobs.reverse[25].name, exact: false do
      click_on "View"
    end
    assert_current_path job_path(added_jobs.reverse[25])
    assert_selector "h1", text: added_jobs.reverse[25].name
  end

  test "browser history restores the filtered paginated list and job activity" do
    added_jobs = Array.new(26) do |index|
      @customer.jobs.create!(name: "Paged job #{index}", status: index.zero? ? "quoted" : "draft")
    end
    job = added_jobs.first
    visit edit_job_path(job)
    select "Draft", from: "Status"
    click_on "Update Job"
    assert_current_path job_path(job)
    within "section[aria-labelledby='activity-heading']" do
      assert_selector "li", count: 1
      assert_text "Job status changed"
      assert_selector "dt", text: "Previous status"
      assert_selector "dd", text: "quoted"
      assert_selector "dt", text: "New status"
      assert_selector "dd", text: "draft"
      assert_text users(:one).email_address
    end

    visit jobs_path(q: "Paged", status: "draft")
    assert_text "Showing 1–25 of 26"
    click_on "Next"
    assert_text "Showing 26–26 of 26"
    within "tbody" do
      click_on "View"
    end
    assert_current_path job_path(added_jobs.first)
    assert_selector "h1", text: added_jobs.first.name
    within "section[aria-labelledby='activity-heading']" do
      assert_selector "li", count: 1
      assert_selector "dd", text: "quoted"
      assert_selector "dd", text: "draft"
    end
    page.go_back
    assert_current_path jobs_path(q: "Paged", status: "draft", page: 2)
    assert_text "Showing 26–26 of 26"
    assert_field "Search jobs", with: "Paged"
    assert_select "Status", selected: "Draft"
    assert_list_records [ job ]
    page.go_forward
    assert_current_path job_path(added_jobs.first)
    assert_selector "h1", text: added_jobs.first.name
    within "section[aria-labelledby='activity-heading']" do
      assert_selector "li", count: 1
      assert_selector "dd", text: "quoted"
      assert_selector "dd", text: "draft"
    end
    activity = job.activities.sole
    assert_equal users(:one), activity.actor
    assert_equal({ "previous_status" => "quoted", "new_status" => "draft" }, activity.metadata)
    assert_empty added_jobs.last.activities
  end

  test "customer pagination preserves ordered owned records through browser history" do
    added_customers = Array.new(26) do |index|
      users(:one).customers.create!(name: format("Paged customer %02d", index))
    end
    users(:two).customers.create!(name: "Paged customer from another account")
    expected_customers = [ @customer ] + added_customers

    visit customers_path
    assert_text "Showing 1–25 of 27"
    assert_list_records expected_customers.first(25)
    click_on "Next"
    assert_current_path customers_path(page: 2)
    assert_text "Showing 26–27 of 27"
    assert_list_records expected_customers.last(2)

    page.go_back
    assert_current_path customers_path
    assert_text "Showing 1–25 of 27"
    assert_list_records expected_customers.first(25)
    page.go_forward
    assert_current_path customers_path(page: 2)
    assert_text "Showing 26–27 of 27"
    assert_list_records expected_customers.last(2)

    within "tbody tr", text: added_customers.last.name do
      click_on "View"
    end
    assert_current_path customer_path(added_customers.last)
    assert_selector "h1", text: added_customers.last.name
    page.go_back
    assert_current_path customers_path(page: 2)
    assert_text "Showing 26–27 of 27"
    assert_list_records expected_customers.last(2)
  end

  test "search and status changes preserve earlier pages in browser history" do
    26.times do |index|
      @customer.jobs.create!(name: "Paged kitchen #{index}", status: "draft")
      @customer.jobs.create!(name: "Paged garage #{index}", status: "completed")
    end

    visit jobs_path
    assert_text "Showing 1–25 of 53"
    click_on "Next"
    assert_text "Showing 26–50 of 53"
    fill_in "Search jobs", with: "Paged"
    assert_current_path jobs_path(q: "Paged", status: "")
    assert_text "Showing 1–25 of 52"

    page.go_back
    assert_current_path jobs_path
    assert_text "Showing 1–25 of 53"
    assert_field "Search jobs", with: ""
    assert_select "Status", selected: "All statuses"
    page.go_forward
    assert_current_path jobs_path(q: "Paged", status: "")
    assert_text "Showing 1–25 of 52"
    assert_field "Search jobs", with: "Paged"
    assert_select "Status", selected: "All statuses"

    click_on "Next"
    assert_text "Showing 26–50 of 52"
    select "Draft", from: "Status"
    assert_current_path jobs_path(q: "Paged", status: "draft")
    assert_text "Showing 1–25 of 26"
    assert_no_selector "tbody tr", text: "Paged garage"

    page.go_back
    assert_current_path jobs_path(q: "Paged", status: "")
    assert_text "Showing 1–25 of 52"
    assert_field "Search jobs", with: "Paged"
    assert_select "Status", selected: "All statuses"
    assert_selector "tbody tr", text: "Paged garage"
    page.go_forward
    assert_current_path jobs_path(q: "Paged", status: "draft")
    assert_text "Showing 1–25 of 26"
    assert_field "Search jobs", with: "Paged"
    assert_select "Status", selected: "Draft"
    assert_no_selector "tbody tr", text: "Paged garage"
  end

  test "debounced search status changes manual submission and reset start at the first page" do
    26.times do |index|
      @customer.jobs.create!(name: "Paged kitchen #{index}", status: "draft")
      @customer.jobs.create!(name: "Paged kitchen #{index}", status: "completed")
    end

    visit jobs_path(q: "Paged", page: 2)
    assert_text "Page 2 of 3"
    fill_in "Search jobs", with: "Paged kitchen"
    assert_text "Page 1 of 3"
    assert_field "Search jobs", with: "Paged kitchen", focused: true
    assert_current_path jobs_path(q: "Paged kitchen", status: "")

    click_on "Next"
    assert_text "Page 2 of 3"
    select "Draft", from: "Status"
    assert_text "Page 1 of 2"
    assert_current_path jobs_path(q: "Paged kitchen", status: "draft")

    click_on "Next"
    assert_text "Page 2 of 2"
    find_field("Search jobs").send_keys(:enter)
    assert_text "Page 1 of 2"
    assert_current_path jobs_path, ignore_query: true
    assert_equal({ "q" => "Paged kitchen", "status" => "draft" },
      Rack::Utils.parse_nested_query(URI.parse(current_url).query).except("commit"))

    click_on "Next"
    assert_text "Page 2 of 2"
    click_on "Reset filters"
    assert_current_path jobs_path
    assert_field "Search jobs", with: ""
    assert_select "Status", selected: "All statuses"
    assert_text "Page 1 of 3"

    page.go_back
    assert_current_path jobs_path(q: "Paged kitchen", status: "draft", page: 2)
    assert_text "Page 2 of 2"
    assert_selector "tbody tr", count: 1
    assert_field "Search jobs", with: "Paged kitchen"
    assert_select "Status", selected: "Draft"
    page.go_forward
    assert_current_path jobs_path
    assert_text "Page 1 of 3"
    assert_selector "tbody tr", count: 25
    assert_field "Search jobs", with: ""
    assert_select "Status", selected: "All statuses"
  end

  test "pagination controls fit phone tablet and desktop viewports for both lists" do
    25.times do |index|
      @customer.jobs.create!(name: "Paged job #{index}")
      users(:one).customers.create!(name: "Paged customer #{index}")
    end

    [ 320, 375, 390, 430, 768, 1400 ].each do |width|
      page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
        width: width, height: 1000, deviceScaleFactor: 1, mobile: false)

      [ customers_path, jobs_path ].each do |path|
        visit path
        within "nav[aria-label='Pagination']" do
          assert_text "Page 1 of 2"
          assert_pagination_fits(width)
          click_on "Next"
          assert_text "Page 2 of 2"
          assert_selector "span[aria-disabled='true']", text: "Next"
          assert_pagination_fits(width)
          click_on "Previous"
          assert_text "Page 1 of 2"
        end
        assert_current_path "#{path}?page=1"
        assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, width
      end
    end
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  private
    def assert_list_records(records)
      expected_paths = records.map { |record| polymorphic_path(record) }
      assert_selector "tbody tr", count: records.size
      assert_selector "tbody" do |table|
        table.all("a", minimum: 0).map { |link| URI.parse(link[:href]).path } == expected_paths
      end
    end

    def assert_pagination_fits(width)
      all("a").each do |link|
        rect = link.evaluate_script("this.getBoundingClientRect().toJSON()")
        assert_operator rect["left"], :>=, 0
        assert_operator rect["right"], :<=, width
        assert_operator rect["width"], :>=, 40
        assert_operator rect["height"], :>=, 40
      end
    end
end
