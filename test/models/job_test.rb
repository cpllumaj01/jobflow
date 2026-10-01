require "test_helper"

class JobTest < ActiveSupport::TestCase
  test "file size validation accepts the limit and rejects larger files" do
    job = jobs(:kitchen_renovation)
    job.files = [{ io: StringIO.new("notes"), filename: "project.txt", content_type: "text/plain" }]
    job.files.first.blob.byte_size = Job::MAX_FILE_SIZE
    assert job.valid?
    job.files.first.blob.byte_size += 1
    assert_not job.valid?
    assert_includes job.errors[:files], "must be 20 MB or smaller per file"
  end

  test "requires a name" do
    job = Job.new(customer: customers(:johnson))

    assert_not job.valid?
    assert_includes job.errors[:name], "can't be blank"
  end

  test "requires a customer" do
    job = Job.new(name: "Kitchen Renovation")

    assert_not job.valid?
    assert_includes job.errors[:customer], "must exist"
  end

  test "defaults to draft status" do
    job = Job.new

    assert_equal "draft", job.status
  end

  test "requires a valid status" do
    job = Job.new(
      customer: customers(:johnson),
      name: "Kitchen Renovation",
      status: "whatever"
    )

    assert_not job.valid?
    assert_includes job.errors[:status], "is not included in the list"
  end

  test "allows multiple change orders for a job" do
    job = jobs(:kitchen_renovation)

    assert_difference("job.change_orders.count", 1) do
      job.change_orders.create!(title: "Additional shelving")
    end
    assert_equal 2, job.change_orders.count
  end

  test "destroying a job destroys its change orders and their line items" do
    assert_difference("ChangeOrder.count", -1) do
      assert_difference("ChangeOrderLineItem.count", -2) do
        jobs(:kitchen_renovation).destroy!
      end
    end

    assert ChangeOrder.exists?(change_orders(:office_outlets).id)
    assert ChangeOrderLineItem.exists?(change_order_line_items(:office_outlets).id)
  end

  test "original estimate value is zero without an estimate" do
    assert_equal 0, jobs(:office_buildout).original_estimate_value
  end

  test "unapproved estimates contribute zero" do
    job = jobs(:kitchen_renovation)
    %w[draft sent rejected].each do |status|
      job.estimate.update!(status: status)
      assert_equal 0, job.original_estimate_value
    end
  end

  test "approved estimate contributes its calculated total" do
    job = jobs(:kitchen_renovation)

    assert_equal BigDecimal("27000"), job.original_estimate_value
  end

  test "approved change order total is zero without change orders" do
    job = customers(:johnson).jobs.create!(name: "Bathroom Remodel")

    assert_equal 0, job.approved_change_order_total
  end

  test "unapproved change orders contribute zero" do
    job = jobs(:kitchen_renovation)
    change_order = change_orders(:kitchen_lighting)

    %w[draft pending rejected].each do |status|
      change_order.update!(status: status)
      assert_equal 0, job.approved_change_order_total
    end
  end

  test "approved change order contributes its calculated total" do
    change_orders(:kitchen_lighting).update!(status: "approved")

    assert_equal BigDecimal("444"), jobs(:kitchen_renovation).approved_change_order_total
  end

  test "multiple approved change orders are summed and other jobs are excluded" do
    job = jobs(:kitchen_renovation)
    change_orders(:kitchen_lighting).update!(status: "approved")
    change_orders(:office_outlets).update!(status: "approved")
    job.change_orders.create!(
      title: "Additional shelving", status: "approved",
      change_order_line_items_attributes: [{ description: "Oak shelves", quantity: "2.5", unit_price: "100.25" }]
    )

    assert_equal BigDecimal("694.625"), job.approved_change_order_total
  end

  test "mixed change order statuses include only approved totals" do
    job = jobs(:kitchen_renovation)
    change_orders(:kitchen_lighting).update!(status: "approved")
    %w[draft pending rejected].each do |status|
      job.change_orders.create!(
        title: "Additional work #{status}", status: status,
        change_order_line_items_attributes: [{ description: "Labor", quantity: 2, unit_price: 100 }]
      )
    end

    assert_equal BigDecimal("444"), job.approved_change_order_total
    assert_equal BigDecimal("27444"), job.current_contract_value
  end

  test "current contract value includes approved estimate without approved change orders" do
    assert_equal BigDecimal("27000"), jobs(:kitchen_renovation).current_contract_value
  end

  test "current contract value includes approved change orders without an estimate" do
    change_orders(:office_outlets).update!(status: "approved")

    assert_equal BigDecimal("500"), jobs(:office_buildout).current_contract_value
  end

  test "current contract value includes approved change orders with an unapproved estimate" do
    job = jobs(:kitchen_renovation)
    change_orders(:kitchen_lighting).update!(status: "approved")
    job.estimate.update!(status: "sent")

    assert_equal BigDecimal("444"), job.current_contract_value
  end

  test "current contract value is zero when neither side is approved or present" do
    assert_equal 0, jobs(:office_buildout).current_contract_value
    job = jobs(:kitchen_renovation)
    job.estimate.update!(status: "draft")
    assert_equal 0, job.current_contract_value
    empty_job = customers(:johnson).jobs.create!(name: "Bathroom Remodel")
    assert_equal 0, empty_job.current_contract_value
  end

  test "current contract value excludes work after approval is withdrawn" do
    job = jobs(:kitchen_renovation)
    change_order = change_orders(:kitchen_lighting)
    change_order.update!(status: "approved")
    assert_equal BigDecimal("27444"), job.current_contract_value

    change_order.update!(status: "pending")
    assert_equal BigDecimal("27000"), job.current_contract_value
    job.estimate.update!(status: "rejected")
    assert_equal 0, job.current_contract_value
  end

  test "preloaded contract values match unloaded values without additional queries" do
    job = jobs(:kitchen_renovation)
    change_orders(:kitchen_lighting).update!(status: "approved")
    %w[draft pending rejected].each do |status|
      job.change_orders.create!(
        title: "Additional work #{status}", status: status,
        change_order_line_items_attributes: [{ description: "Labor", quantity: 2, unit_price: 100 }]
      )
    end
    expected_value = job.current_contract_value
    preloaded_job = Job.includes(estimate: :estimate_line_items, change_orders: :change_order_line_items).find(job.id)

    assert_no_queries do
      assert_equal BigDecimal("444"), preloaded_job.approved_change_order_total
      assert_equal expected_value, preloaded_job.current_contract_value
    end
  end
end
