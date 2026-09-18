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
end
