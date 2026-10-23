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
    page.execute_script("window.paginationSearchField = document.querySelector('input[name=q]')")

    within "nav[aria-label='Pagination']" do
      click_on "Next"
    end
    assert_text "Showing 26–50 of 51"
    assert_current_path jobs_path(q: "Paged", status: "draft", page: 2)
    assert page.evaluate_script("window.paginationSearchField === document.querySelector('input[name=q]')")
    assert_no_selector "html[aria-busy], turbo-frame[busy]"

    within "nav[aria-label='Pagination']" do
      click_on "Next"
    end
    assert_text "Showing 51–51 of 51"
    assert_current_path jobs_path(q: "Paged", status: "draft", page: 3)
    assert_no_selector "html[aria-busy], turbo-frame[busy]"
    page.go_back
    assert_text "Showing 26–50 of 51"
    assert_current_path jobs_path(q: "Paged", status: "draft", page: 2)
    assert_no_selector "html[aria-busy], turbo-frame[busy]"
    page.go_back
    assert_current_path jobs_path(q: "Paged", status: "draft")
    assert_text "Showing 1–25 of 51"
    assert_field "Search jobs", with: "Paged"
    assert_select "Status", selected: "Draft"
    page.go_forward
    assert_text "Showing 26–50 of 51"
    assert_current_path jobs_path(q: "Paged", status: "draft", page: 2)
    assert_field "Search jobs", with: "Paged"
    assert_select "Status", selected: "Draft"

    within "tbody tr", text: added_jobs.reverse[25].name, exact: false do
      click_on "View"
    end
    assert_current_path job_path(added_jobs.reverse[25])
    assert_selector "h1", text: added_jobs.reverse[25].name
  end

  test "browser history returns from a job to the filtered paginated list" do
    added_jobs = Array.new(26) do |index|
      @customer.jobs.create!(name: "Paged job #{index}", status: "draft")
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
    page.go_back
    assert_current_path jobs_path(q: "Paged", status: "draft", page: 2)
    assert_text "Showing 26–26 of 26"
    assert_field "Search jobs", with: "Paged"
    assert_select "Status", selected: "Draft"
    assert_selector "tbody tr", count: 1
    assert_selector "tbody tr", text: added_jobs.first.name
    page.go_forward
    assert_current_path job_path(added_jobs.first)
    assert_selector "h1", text: added_jobs.first.name
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

    [ 375, 768, 1400 ].each do |width|
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
    page.execute_script("window.paginationSearchField = document.querySelector('input[name=q]')")

    within "nav[aria-label='Pagination']" do
      click_on "Next"
    end
    assert_text "Showing 26–50 of 51"
    assert_current_path jobs_path(q: "Paged", status: "draft", page: 2)
    assert page.evaluate_script("window.paginationSearchField === document.querySelector('input[name=q]')")
    assert_no_selector "html[aria-busy], turbo-frame[busy]"

    within "nav[aria-label='Pagination']" do
      click_on "Next"
    end
    assert_text "Showing 51–51 of 51"
    assert_no_selector "html[aria-busy], turbo-frame[busy]"
    page.go_back
    assert_text "Showing 26–50 of 51"
    assert_current_path jobs_path(q: "Paged", status: "draft", page: 2)
    assert_no_selector "html[aria-busy], turbo-frame[busy]"
    page.go_back
    assert_text "Showing 1–25 of 51"
    assert_current_path jobs_path(q: "Paged", status: "draft")
    page.go_forward
    assert_text "Showing 26–50 of 51"
    assert_field "Search jobs", with: "Paged"
    assert_select "Status", selected: "Draft"

    within "tbody tr", text: added_jobs.reverse[25].name, exact: false do
      click_on "View"
    end
    assert_current_path job_path(added_jobs.reverse[25])
    assert_selector "h1", text: added_jobs.reverse[25].name
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
    assert_text "Page 2 of 2"
    assert_field "Search jobs", with: "Paged kitchen"
    assert_select "Status", selected: "Draft"
    page.go_forward
    assert_text "Page 1 of 3"
    assert_field "Search jobs", with: ""
    assert_select "Status", selected: "All statuses"
  end

  test "pagination controls fit phone tablet and desktop viewports for both lists" do
    25.times do |index|
      @customer.jobs.create!(name: "Paged job #{index}")
      users(:one).customers.create!(name: "Paged customer #{index}")
    end

    [ 375, 768, 1400 ].each do |width|
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
