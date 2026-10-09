require "application_system_test_case"

class LineItemFormsTest < ApplicationSystemTestCase
  setup do
    @job = jobs(:kitchen_renovation)
    @estimate = estimates(:kitchen_estimate)
    @estimate.update!(status: "draft")
    @change_order = change_orders(:kitchen_lighting)

    visit new_session_path
    fill_in "Email address", with: users(:one).email_address
    fill_in "Password", with: "password"
    click_on "Sign in"
    assert_button "Log out"
  end

  test "new estimate starts with one editable line item" do
    open_new_estimate

    assert_selector "[data-testid=line-item]", count: 1
    within line_item("") do
      assert_field "Description", with: ""
      assert_field "Quantity", with: ""
      assert_field "Unit price", with: ""
      assert_button "Remove"
    end
  end

  test "estimate Add line item adds another editable row" do
    open_new_estimate
    fill_line_item "Original work"

    click_on "Add line item"
    assert_selector "[data-testid=line-item]", count: 2
    fill_line_item "Additional work", quantity: "3", unit_price: "75"

    within line_item("Additional work") do
      assert_field "Quantity", with: "3"
      assert_field "Unit price", with: "75"
    end
    assert_field "Description", with: "Original work"
  end

  test "estimate removes a newly added unsaved line item" do
    open_new_estimate
    fill_line_item "Keep this work"
    click_on "Add line item"
    fill_line_item "Remove this work"

    within line_item("Remove this work") do
      click_on "Remove"
    end

    assert_selector "[data-testid=line-item]", count: 1
    assert_no_field "Description", with: "Remove this work"
    assert_field "Description", with: "Keep this work"
  end

  test "estimate deletes a persisted line item when saved" do
    removed = estimate_line_items(:cabinets)
    original_count = @estimate.estimate_line_items.count
    open_edit_estimate

    within line_item(removed.description) do
      click_on "Remove"
    end
    assert_no_field "Description", with: removed.description
    click_on @submit

    assert_text "successfully updated"
    assert_not removed.class.exists?(removed.id)
    assert_equal original_count - 1, @estimate.estimate_line_items.reload.count
  end

  test "estimate saves multiple dynamically added line items" do
    open_new_estimate
    fill_line_item "Original work"
    click_on "Add line item"
    fill_line_item "Materials", quantity: "3", unit_price: "25"
    click_on "Add line item"
    fill_line_item "Labor", quantity: "2", unit_price: "80"

    click_on @submit

    assert_text "successfully created"
    assert_text "Original work"
    assert_text "Materials"
    assert_text "Labor"
    saved = @job.reload.estimate.estimate_line_items
    assert_equal 3, saved.count
    assert_equal BigDecimal("75"), saved.find_by!(description: "Materials").line_total
    assert_equal BigDecimal("160"), saved.find_by!(description: "Labor").line_total
  end

  test "estimate preserves entered values and removal through validation failure" do
    removed = estimate_line_items(:cabinets)
    open_edit_estimate
    within line_item(removed.description) do
      click_on "Remove"
    end
    click_on "Add line item"
    fill_line_item "Additional work", quantity: "", unit_price: "25"

    click_on @submit

    assert_text "quantity is not a number"
    assert_no_field "Description", with: removed.description
    assert removed.class.exists?(removed.id)
    within line_item("Additional work") do
      assert_field "Quantity", with: ""
      assert_field "Unit price", with: "25"
      fill_in "Quantity", with: "3"
    end
    click_on @submit

    assert_text "successfully updated"
    assert_not removed.class.exists?(removed.id)
    assert_equal BigDecimal("75"), @estimate.estimate_line_items.find_by!(description: "Additional work").line_total
  end

  test "new change order starts with one editable line item" do
    open_new_change_order

    assert_selector "[data-testid=line-item]", count: 1
    within line_item("") do
      assert_field "Description", with: ""
      assert_field "Quantity", with: ""
      assert_field "Unit price", with: ""
      assert_button "Remove"
    end
  end

  test "change order Add line item adds another editable row" do
    open_new_change_order
    fill_line_item "Original work"

    click_on "Add line item"
    assert_selector "[data-testid=line-item]", count: 2
    fill_line_item "Additional work", quantity: "3", unit_price: "75"

    within line_item("Additional work") do
      assert_field "Quantity", with: "3"
      assert_field "Unit price", with: "75"
    end
    assert_field "Description", with: "Original work"
  end

  test "change order removes a newly added unsaved line item" do
    open_new_change_order
    fill_line_item "Keep this work"
    click_on "Add line item"
    fill_line_item "Remove this work"

    within line_item("Remove this work") do
      click_on "Remove"
    end

    assert_selector "[data-testid=line-item]", count: 1
    assert_no_field "Description", with: "Remove this work"
    assert_field "Description", with: "Keep this work"
  end

  test "change order deletes a persisted line item when saved" do
    removed = change_order_line_items(:lighting_materials)
    original_count = @change_order.change_order_line_items.count
    open_edit_change_order

    within line_item(removed.description) do
      click_on "Remove"
    end
    assert_no_field "Description", with: removed.description
    click_on @submit

    assert_text "successfully updated"
    assert_not removed.class.exists?(removed.id)
    assert_equal original_count - 1, @change_order.change_order_line_items.reload.count
  end

  test "change order saves multiple dynamically added line items" do
    open_new_change_order
    fill_line_item "Original work"
    click_on "Add line item"
    fill_line_item "Materials", quantity: "3", unit_price: "25"
    click_on "Add line item"
    fill_line_item "Labor", quantity: "2", unit_price: "80"

    click_on @submit

    assert_text "successfully created"
    assert_text "Original work"
    assert_text "Materials"
    assert_text "Labor"
    saved = @job.change_orders.find_by!(title: "Extra work").change_order_line_items
    assert_equal 3, saved.count
    assert_equal BigDecimal("75"), saved.find_by!(description: "Materials").line_total
    assert_equal BigDecimal("160"), saved.find_by!(description: "Labor").line_total
  end

  test "change order preserves entered values and removal through validation failure" do
    removed = change_order_line_items(:lighting_materials)
    open_edit_change_order
    within line_item(removed.description) do
      click_on "Remove"
    end
    click_on "Add line item"
    fill_line_item "Additional work", quantity: "", unit_price: "25"

    click_on @submit

    assert_text "quantity is not a number"
    assert_no_field "Description", with: removed.description
    assert removed.class.exists?(removed.id)
    within line_item("Additional work") do
      assert_field "Quantity", with: ""
      assert_field "Unit price", with: "25"
      fill_in "Quantity", with: "3"
    end
    click_on @submit

    assert_text "successfully updated"
    assert_not removed.class.exists?(removed.id)
    assert_equal BigDecimal("75"), @change_order.change_order_line_items.find_by!(description: "Additional work").line_total
  end

  private
    def open_new_estimate
      @job = customers(:johnson).jobs.create!(name: "New estimate job")
      visit new_job_estimate_path(@job)
      @submit = "Create Estimate"
    end

    def open_edit_estimate
      visit edit_job_estimate_path(@job)
      @submit = "Update Estimate"
    end

    def open_new_change_order
      visit new_job_change_order_path(@job)
      fill_in "Title", with: "Extra work"
      @submit = "Create Change order"
    end

    def open_edit_change_order
      visit edit_job_change_order_path(@job, @change_order)
      @submit = "Update Change order"
    end

    def line_item(description)
      find("[data-testid=line-item]") do |row|
        row.has_field?("Description", with: description, wait: 0)
      end
    end

    def fill_line_item(description, quantity: "2", unit_price: "50")
      within line_item("") do
        fill_in "Description", with: description
        fill_in "Quantity", with: quantity
        fill_in "Unit price", with: unit_price
      end
    end
end
