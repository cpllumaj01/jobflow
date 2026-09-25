require "test_helper"

class EstimateTest < ActiveSupport::TestCase
  test "calculates total from line items" do
    estimate = estimates(:kitchen_estimate)

    assert_equal 27_000, estimate.total
  end

  test "requires valid status" do
    estimate = Estimate.new(
      job: jobs(:office_buildout),
      status: "whatever"
    )

    assert_not estimate.valid?
    assert_includes estimate.errors[:status], "is not included in the list"
  end

  test "defaults to draft status" do
    estimate = Estimate.new

    assert_equal "draft", estimate.status
  end

  test "ignores blank nested line items" do
    estimate = Estimate.new(job: jobs(:office_buildout), estimate_line_items_attributes: [
      { description: " ", quantity: "", unit_price: "" }
    ])

    assert estimate.valid?
    assert_empty estimate.estimate_line_items
  end

  test "validates partially completed nested line items" do
    estimate = Estimate.new(job: jobs(:office_buildout), estimate_line_items_attributes: [
      { description: "Labor", quantity: "", unit_price: "" }
    ])

    assert_not estimate.valid?
    assert_equal 1, estimate.estimate_line_items.size
  end

  test "does not ignore blanked existing line items" do
    estimate = estimates(:kitchen_estimate)
    estimate.assign_attributes(estimate_line_items_attributes: [
      { id: estimate_line_items(:cabinets).id, description: "", quantity: "", unit_price: "" }
    ])

    assert_not estimate.valid?
  end
end
