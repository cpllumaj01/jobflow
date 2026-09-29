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
      change_order_line_items_attributes: [{ description: "Tile", quantity: 2, unit_price: "100.25" }]
    )
    customers(:johnson).jobs.create!(name: "No financial items")
    jobs(:office_buildout).create_estimate!(
      status: "approved",
      estimate_line_items_attributes: [{ description: "Office work", quantity: 1, unit_price: 90000 }]
    )
    change_orders(:office_outlets).update!(status: "approved")

    get root_url

    assert_response :success
    assert_select "#total_current_contract_value dd", "$27,644.50"
  end

  test "unapproved financial items contribute zero" do
    estimate = estimates(:kitchen_estimate)
    %w[draft pending rejected].each do |status|
      jobs(:kitchen_renovation).change_orders.create!(
        title: "Unapproved work #{status}", status: status,
        change_order_line_items_attributes: [{ description: "Labor", quantity: 2, unit_price: 100 }]
      )
    end
    change_orders(:office_outlets).update!(status: "approved")

    %w[draft sent rejected].each do |status|
      estimate.update!(status: status)
      get root_url
      assert_select "#total_current_contract_value dd", "$0.00"
    end
  end

  test "a user without records sees zero metrics despite another user's work" do
    user = User.create!(email_address: "new-owner@example.com", password: "password")
    sign_in_as user

    get root_url

    assert_response :success
    %w[total_customers total_jobs active_jobs pending_estimates pending_change_orders].each do |metric|
      assert_select "##{metric} dd", "0"
    end
    assert_select "#total_current_contract_value dd", "$0.00"
  end

  test "dashboard requires authentication" do
    sign_out
    get root_url

    assert_redirected_to new_session_url
  end
end
