require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
  end

  test "counts only the current user's customers and jobs" do
    customers(:johnson).jobs.create!(name: "Bathroom Remodel")
    users(:one).customers.create!(name: "Smith Residence")
    users(:two).customers.create!(name: "Other customer")
    customers(:fairfield).jobs.create!(name: "Other job")

    get root_url

    assert_response :success
    assert_select "#total_customers dd", "2"
    assert_select "#total_jobs dd", "2"
    assert_select "a[href=?]", customers_path
    assert_select "a[href=?]", jobs_path
    assert_select "h2", text: "Get started with JobFlow", count: 0
  end

  test "active jobs are approved or in progress only" do
    job = jobs(:kitchen_renovation)
    jobs(:office_buildout).update!(status: "in_progress")

    { "draft" => 0, "quoted" => 0, "approved" => 1, "in_progress" => 1, "completed" => 0, "cancelled" => 0 }.each do |status, expected|
      job.update!(status: status)
      get root_url
      assert_select "#active_jobs dd", expected.to_s
    end
  end

  test "pending estimates are sent estimates from owned jobs only" do
    jobs(:office_buildout).create_estimate!(status: "sent")
    estimate = estimates(:kitchen_estimate)

    { "draft" => 0, "sent" => 1, "approved" => 0, "rejected" => 0 }.each do |status, expected|
      estimate.update!(status: status)
      get root_url
      assert_select "#pending_estimates dd", expected.to_s
    end
  end

  test "pending change orders are pending orders from owned jobs only" do
    change_order = change_orders(:kitchen_lighting)

    { "draft" => 0, "pending" => 1, "approved" => 0, "rejected" => 0 }.each do |status, expected|
      change_order.update!(status: status)
      get root_url
      assert_select "#pending_change_orders dd", expected.to_s
    end
  end

  test "contract value includes approved work across owned jobs and excludes other users" do
    change_orders(:kitchen_lighting).update!(status: "approved")
    second_job = customers(:johnson).jobs.create!(name: "Bathroom Remodel", status: "completed")
    second_job.change_orders.create!(
      title: "Tile upgrade", status: "approved",
      change_order_line_items_attributes: [ { description: "Tile", quantity: 2, unit_price: "100.25" } ]
    )
    customers(:johnson).jobs.create!(name: "No financial items")
    jobs(:office_buildout).create_estimate!(
      status: "approved",
      estimate_line_items_attributes: [ { description: "Office work", quantity: 1, unit_price: 90000 } ]
    )
    change_orders(:office_outlets).update!(status: "approved")

    get root_url

    assert_response :success
    assert_select "#total_current_contract_value dd", "$27,644.50"
    assert_select "#approved_estimate_value dd span", "$27,000.00"
    assert_select "#approved_change_order_value dd span", "$644.50"
    assert_select "#contract_breakdown [aria-hidden=true] span[style]", count: 2
  end

  test "unapproved financial items contribute zero" do
    estimate = estimates(:kitchen_estimate)
    %w[draft pending rejected].each do |status|
      jobs(:kitchen_renovation).change_orders.create!(
        title: "Unapproved work #{status}", status: status,
        change_order_line_items_attributes: [ { description: "Labor", quantity: 2, unit_price: 100 } ]
      )
    end
    change_orders(:office_outlets).update!(status: "approved")

    %w[draft sent rejected].each do |status|
      estimate.update!(status: status)
      get root_url
      assert_select "#total_current_contract_value dd", "$0.00"
      assert_select "#contract_breakdown", count: 0
      assert_select "h3", "No approved contract value yet"
    end
  end

  test "a user without records sees zero metrics despite another user's work" do
    user = User.create!(email_address: "new-owner@example.com", password: "passwordpassword")
    sign_in_as user

    get root_url

    assert_response :success
    %w[total_customers total_jobs active_jobs pending_estimates pending_change_orders].each do |metric|
      assert_select "##{metric} dd", "0"
    end
    assert_select "#total_current_contract_value dd", "$0.00"
    assert_select "h2", "Get started with JobFlow"
    assert_select "p", "Add your first customer, then create a job to track estimates and changes in one place."
    assert_select "main a[href=?]", customers_path, count: 1
    assert_select "a[href=?]", new_customer_path, text: "Add first customer"
    assert_select "#jobs_by_status, #contract_breakdown", count: 0
    assert_select "main", text: /No approvals outstanding/
  end

  test "a user with customers and no jobs sees the next step" do
    user = User.create!(email_address: "customer-owner@example.com", password: "passwordpassword")
    user.customers.create!(name: "First customer")
    sign_in_as user

    get root_url

    assert_response :success
    assert_select "h2", "Get started with JobFlow"
    assert_select "p", "Create your first job to start tracking work, estimates, and change orders."
    assert_select "main a[href=?]", jobs_path, count: 1
    assert_select "a[href=?]", new_job_path, text: "Create first job"
    assert_select "#jobs_by_status, #contract_breakdown", count: 0
  end

  test "customer and job metrics link to their matching owned lists" do
    get root_url
    customer_link = css_select("main a").find { |link| link.at_css("#total_customers") }
    job_link = css_select("main a").find { |link| link.at_css("#total_jobs") }
    assert_equal customers_path, customer_link["href"]
    assert_equal jobs_path, job_link["href"]

    get customer_link["href"]
    assert_select "tbody tr", count: 1
    assert_select "tbody tr", text: /#{customers(:johnson).name}/
    assert_select "tbody tr", text: /#{customers(:fairfield).name}/, count: 0

    get job_link["href"]
    assert_select "tbody tr", count: 1
    assert_select "tbody tr", text: /#{jobs(:kitchen_renovation).name}/
    assert_select "tbody tr", text: /#{jobs(:office_buildout).name}/, count: 0
  end

  test "active jobs drill down uses repeatable status parameters and matching records" do
    approved = customers(:johnson).jobs.create!(name: "Approved work", status: "approved")
    completed = customers(:johnson).jobs.create!(name: "Finished work", status: "completed")
    jobs(:office_buildout).update!(status: "approved")

    get root_url
    assert_select "#active_jobs dd", "2"
    link = css_select("main a").find { |element| element.at_css("#active_jobs") }
    assert_equal jobs_path(status: %w[approved in_progress]), link["href"]

    get link["href"]
    assert_select "input[name='status[]'][checked]", count: 2
    assert_select "tbody tr", count: 2
    [ approved, jobs(:kitchen_renovation) ].each do |job|
      assert_select "tbody tr", text: /#{job.name}/
    end
    [ completed, jobs(:office_buildout) ].each do |job|
      assert_select "tbody tr", text: /#{job.name}/, count: 0
    end
  end

  test "status chart counts and drill downs reconcile with all owned jobs" do
    Job::STATUSES.each_with_index do |status, index|
      (index + 1).times { |number| customers(:johnson).jobs.create!(name: "#{status} job #{number}", status: status) }
    end
    jobs(:office_buildout).update!(status: "completed")

    get root_url
    assert_select "#total_jobs dd", "22"
    assert_select "#jobs_by_status li", count: Job::STATUSES.size
    Job::STATUSES.each_with_index do |status, index|
      count = index + 1 + (status == "in_progress" ? 1 : 0)
      assert_select "#jobs_by_status a[href=?]", jobs_path(status: [ status ]) do
        assert_select "[aria-hidden=true] span[style=?]", "width: #{(count.fdiv(22) * 100).round(2)}%"
        assert_select "span", count.to_s
      end
    end
    links = css_select("#jobs_by_status a").map { |link| link["href"] }
    Job::STATUSES.zip(links).each_with_index do |(status, path), index|
      get path
      assert_select "tbody tr", count: index + 1 + (status == "in_progress" ? 1 : 0)
      assert_select "tbody tr span", text: status.humanize, count: index + 1 + (status == "in_progress" ? 1 : 0)
      assert_select "tbody tr", text: /#{jobs(:office_buildout).name}/, count: 0
    end
  end

  test "single status dataset shows full and zero proportions with accessible labels" do
    get root_url

    assert_select "#jobs_by_status[aria-labelledby='job-status-title'][aria-describedby='job-status-description']"
    assert_select "#jobs_by_status a[aria-label='In progress: 1 job']" do
      assert_select "span[style='width: 100.0%']"
    end
    assert_select "#jobs_by_status a[aria-label='Draft: 0 jobs']" do
      assert_select "span[style='width: 0.0%']"
    end
    assert_select "#contract_breakdown[aria-labelledby='contract-breakdown-title']"
    assert_select "#approved_estimate_value dd span", "$27,000.00"
    assert_select "#approved_change_order_value dd span", "$0.00"
  end

  test "approved change orders count without an approved estimate" do
    estimates(:kitchen_estimate).update!(status: "sent")
    change_orders(:kitchen_lighting).update!(status: "approved")

    get root_url

    assert_select "#approved_estimate_value dd span", "$0.00"
    assert_select "#approved_change_order_value dd span", "$444.00"
    assert_select "#total_current_contract_value dd", "$444.00"
    assert_select "#pending_estimates dd", "1"
  end

  test "jobs without financial records retain counts and show an honest financial empty state" do
    user = User.create!(email_address: "unpriced-owner@example.com", password: "passwordpassword")
    user.customers.create!(name: "Unpriced customer").jobs.create!(name: "Unpriced job", status: "approved")
    sign_in_as user

    get root_url

    assert_select "#total_jobs dd", "1"
    assert_select "#active_jobs dd", "1"
    assert_select "#total_current_contract_value dd", "$0.00"
    assert_select "#pending_estimates dd", "0"
    assert_select "#pending_change_orders dd", "0"
    assert_select "#jobs_by_status a[aria-label='Approved: 1 job']"
    assert_select "#contract_breakdown, #onboarding-title", count: 0
    assert_select "h3", "No approved contract value yet"
  end

  test "pending and financial summaries have no misleading navigation" do
    get root_url

    %w[pending_estimates pending_change_orders total_current_contract_value].each do |id|
      element = css_select("##{id}").sole
      assert_empty element.css("a")
      assert_empty element.ancestors("a")
    end
    assert_select "main a[href=?]", customers_path, count: 1
    assert_select "main a[href=?]", jobs_path, count: 1
  end

  test "dashboard requires authentication" do
    sign_out
    get root_url

    assert_redirected_to new_session_url
  end
end
