require "test_helper"

class ChangeOrderTest < ActiveSupport::TestCase
  test "defaults to draft status" do
    change_order = jobs(:kitchen_renovation).change_orders.create!(title: "Additional shelving")

    assert_equal "draft", change_order.reload.status
  end

  test "accepts valid statuses" do
    change_order = change_orders(:kitchen_lighting)

    ChangeOrder::STATUSES.each do |status|
      change_order.status = status
      assert change_order.valid?, change_order.errors.full_messages.to_sentence
    end
  end

  test "requires a valid status" do
    change_order = change_orders(:kitchen_lighting)
    change_order.status = "whatever"

    assert_not change_order.valid?
    assert_includes change_order.errors[:status], "is not included in the list"
  end

  test "requires a title" do
    change_order = ChangeOrder.new(job: jobs(:kitchen_renovation))

    assert_not change_order.valid?
    assert_includes change_order.errors[:title], "can't be blank"
  end

  test "requires a job" do
    change_order = ChangeOrder.new(title: "Additional shelving")

    assert_not change_order.valid?
    assert_includes change_order.errors[:job], "must exist"
  end

  test "calculates total from multiple line items" do
    assert_equal BigDecimal("444.00"), change_orders(:kitchen_lighting).total
  end

  test "total is zero without line items" do
    assert_equal 0, ChangeOrder.new.total
  end

  test "creates nested line items and ignores completely blank rows" do
    change_order = jobs(:kitchen_renovation).change_orders.new(
      title: "Additional shelving",
      change_order_line_items_attributes: [
        { description: "Oak shelves", quantity: "2", unit_price: "125.25" },
        { description: " ", quantity: "", unit_price: "" }
      ]
    )

    assert_difference("ChangeOrderLineItem.count", 1) { change_order.save! }
    assert_equal 1, change_order.reload.change_order_line_items.count
    assert_equal BigDecimal("250.50"), change_order.total
  end

  test "partially completed nested rows are validated" do
    change_order = ChangeOrder.new(
      job: jobs(:kitchen_renovation), title: "Additional shelving",
      change_order_line_items_attributes: [ { description: "Oak shelves", quantity: "", unit_price: "" } ]
    )

    assert_not change_order.valid?
    assert_equal 1, change_order.change_order_line_items.size
  end

  test "updates and removes nested line items" do
    change_order = change_orders(:kitchen_lighting)
    materials = change_order_line_items(:lighting_materials)
    labor = change_order_line_items(:lighting_labor)

    assert_difference("ChangeOrderLineItem.count", -1) do
      change_order.update!(change_order_line_items_attributes: [
        { id: materials.id, quantity: "4" },
        { id: labor.id, _destroy: "1" }
      ])
    end

    assert_equal 4, materials.reload.quantity
    assert_not ChangeOrderLineItem.exists?(labor.id)
  end

  test "destroying a change order destroys its line items" do
    change_order = change_orders(:kitchen_lighting)

    assert_difference("ChangeOrderLineItem.count", -2) { change_order.destroy! }
    assert ChangeOrderLineItem.exists?(change_order_line_items(:office_outlets).id)
  end

  test "approval sets its timestamp and repeated approval preserves it" do
    change_order = change_orders(:kitchen_lighting)

    freeze_time do
      change_order.update!(status: "approved")
      assert_equal Time.current, change_order.reload.approved_at
    end

    approved_at = change_order.approved_at
    travel 1.hour do
      change_order.update!(status: "approved")
      assert_equal approved_at, change_order.reload.approved_at
    end
  end

  test "every non-approved status clears stale approval timestamps" do
    change_order = change_orders(:kitchen_lighting)

    %w[draft pending rejected].each do |status|
      change_order.update!(status: "approved")
      change_order.update!(status: status)
      assert_nil change_order.reload.approved_at

      change_order.update!(approved_at: Time.current)
      assert_nil change_order.reload.approved_at
    end
  end

  test "reapproval records a new approval time" do
    change_order = change_orders(:kitchen_lighting)
    change_order.update!(status: "approved")
    previous_approval = change_order.approved_at
    change_order.update!(status: "rejected")

    travel 1.hour do
      change_order.update!(status: "approved")
      assert_equal Time.current, change_order.reload.approved_at
      assert_operator change_order.approved_at, :>, previous_approval
    end
  end
end
