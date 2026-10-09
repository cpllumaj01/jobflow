require "test_helper"

class ChangeOrderLineItemTest < ActiveSupport::TestCase
  test "calculates decimal line total" do
    line_item = ChangeOrderLineItem.new(quantity: "2.5", unit_price: "75.50")

    assert_equal BigDecimal("188.75"), line_item.line_total
  end

  test "requires a description" do
    line_item = change_order_line_items(:lighting_materials)
    line_item.description = ""

    assert_not line_item.valid?
    assert_includes line_item.errors[:description], "can't be blank"
  end

  test "requires a change order" do
    line_item = ChangeOrderLineItem.new(description: "LED lighting kit", quantity: 1, unit_price: 85)

    assert_not line_item.valid?
    assert_includes line_item.errors[:change_order], "must exist"
  end

  test "quantity must be greater than zero" do
    line_item = change_order_line_items(:lighting_materials)

    [ 0, -1, nil ].each do |quantity|
      line_item.quantity = quantity
      assert_not line_item.valid?
      assert line_item.errors[:quantity].present?
    end
  end

  test "positive fractional quantity is valid" do
    line_item = change_order_line_items(:lighting_labor)

    assert line_item.valid?, line_item.errors.full_messages.to_sentence
  end

  test "unit price cannot be negative" do
    line_item = change_order_line_items(:lighting_materials)
    line_item.unit_price = -1

    assert_not line_item.valid?
    assert_includes line_item.errors[:unit_price], "must be greater than or equal to 0"
  end

  test "unit price can be zero" do
    line_item = change_order_line_items(:lighting_materials)
    line_item.unit_price = 0

    assert line_item.valid?, line_item.errors.full_messages.to_sentence
  end
end
