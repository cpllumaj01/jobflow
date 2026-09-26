require "test_helper"

class JobTest < ActiveSupport::TestCase
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
end
