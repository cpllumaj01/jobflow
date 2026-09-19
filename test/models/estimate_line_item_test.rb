require "test_helper"

class EstimateLineItemTest < ActiveSupport::TestCase
  test "calculates line total" do
    line_item = EstimateLineItem.new(
      quantity: 2.5,
      unit_price: 100
    )

    assert_equal 250, line_item.line_total
  end

  test "requires description" do
    line_item = EstimateLineItem.new(
      estimate: estimates(:kitchen_estimate),
      quantity: 1,
      unit_price: 100
    )

    assert_not line_item.valid?
    assert_includes line_item.errors[:description], "can't be blank"
  end

  test "quantity must be greater than zero" do
    line_item = EstimateLineItem.new(
      estimate: estimates(:kitchen_estimate),
      description: "Labor",
      quantity: 0,
      unit_price: 100
    )

    assert_not line_item.valid?
  end

  test "unit price cannot be negative" do
    line_item = EstimateLineItem.new(
      estimate: estimates(:kitchen_estimate),
      description: "Labor",
      quantity: 1,
      unit_price: -100
    )

    assert_not line_item.valid?
  end

  test "unit price can be zero" do
    line_item = EstimateLineItem.new(
      estimate: estimates(:kitchen_estimate),
      description: "Complimentary labor",
      quantity: 1,
      unit_price: 0
    )

    assert line_item.valid?, line_item.errors.full_messages.to_sentence
  end
end
