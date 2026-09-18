require "test_helper"

class CustomerTest < ActiveSupport::TestCase
  test "requires a name" do
    customer = Customer.new(user: users(:one))

    assert_not customer.valid?
    assert_includes customer.errors[:name], "can't be blank"
  end

  test "belongs to a user" do
    customer = Customer.new(name: "Johnson Residence")

    assert_not customer.valid?
    assert_includes customer.errors[:user], "must exist"
  end
end
