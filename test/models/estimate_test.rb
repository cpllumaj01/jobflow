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
end
