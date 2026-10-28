require "application_system_test_case"

class ResponsiveLayoutTest < ApplicationSystemTestCase
  setup do
    @customer = customers(:johnson)
    @job = jobs(:kitchen_renovation)
    @change_order = change_orders(:kitchen_lighting)
    @customer.update!(name: "Johnson Residence and Workshop", email: "#{'longaddress' * 5}@example.com")
    @job.update!(name: "Kitchen renovation and workshop improvements", description: "Project details #{'unbroken' * 30}")
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
  end

  [ 375, 768, 1400 ].each do |width|
    test "core screens fit a #{width}px viewport" do
      set_viewport(width)

      within "nav[aria-label='Main navigation']" do
        click_on "Customers"
      end
      assert_current_path customers_path
      assert_scrollable_table "Customers", width
      within "nav[aria-label='Main navigation']" do
        click_on "Jobs", exact: true
      end
      assert_current_path jobs_path
      fill_in "Search jobs", with: "kitchen"
      assert_selector "tbody tr", count: 1
      assert_text @job.name
      assert_scrollable_table "Jobs", width

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

  test "line items can be added removed and saved on phones and tablets" do
    [ 375, 768 ].each do |width|
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

  private
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
        width: width, height: 1000, deviceScaleFactor: 1, mobile: false)
      assert_equal width, page.evaluate_script("window.innerWidth")
    end

    def assert_layout_fits(width, path)
      assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, width,
        "Page overflow at #{width}px on #{path}"

      outside = page.evaluate_script(<<~JS)
        Array.from(document.querySelectorAll('nav a, nav button, main input:not([type=hidden]), main select, main textarea, main button, main a')).filter(element => {
          if (!element.getClientRects().length || element.closest('[role=region]')) return false;
          const rect = element.getBoundingClientRect();
          return rect.left < 0 || rect.right > window.innerWidth + 1 || rect.width < 24 || rect.height < 24;
        }).map(element => element.textContent.trim() || element.name)
      JS
      assert_empty outside, "Controls outside viewport or too small on #{path}: #{outside.inspect}"
    end

    def assert_scrollable_table(label, width)
      region = find("[role=region][aria-label='#{label}']")
      assert_layout_fits(width, current_path)
      if width == 375
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
