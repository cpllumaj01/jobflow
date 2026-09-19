require "test_helper"

class EstimatesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @job = jobs(:kitchen_renovation)
    @estimate = estimates(:kitchen_estimate)

    sign_in_as @user
  end

  test "should show estimate" do
    get job_estimate_url(@job)

    assert_response :success
    assert_select "body", text: /27,000/
  end

  test "should get new for job without estimate" do
    job = @user.customers.first.jobs.create!(
      name: "Bathroom Remodel"
    )

    get new_job_estimate_url(job)

    assert_response :success
  end

  test "new redirects when job already has estimate" do
    get new_job_estimate_url(@job)

    assert_redirected_to job_estimate_url(@job)
  end

  test "should create estimate with line items" do
    job = @user.customers.first.jobs.create!(
      name: "Deck Replacement"
    )

    assert_difference(["Estimate.count", "EstimateLineItem.count"], 1) do
      post job_estimate_url(job), params: {
        estimate: {
          notes: "Deck estimate",
          expires_on: "2026-10-31",
          estimate_line_items_attributes: {
            "0" => {
              description: "Lumber",
              quantity: 10,
              unit_price: 50
            }
          }
        }
      }
    end

    estimate = job.reload.estimate

    assert_equal "draft", estimate.status
    assert_equal 500, estimate.total
    assert_redirected_to job_estimate_url(job)
  end

  test "create redirects when job already has estimate" do
    assert_no_difference("Estimate.count") do
      post job_estimate_url(@job), params: {
        estimate: {
          notes: "Another estimate"
        }
      }
    end

    assert_redirected_to job_estimate_url(@job)
  end

  test "should get edit" do
    get edit_job_estimate_url(@job)

    assert_response :success
  end

  test "should update estimate and line item" do
    line_item = estimate_line_items(:cabinets)

    patch job_estimate_url(@job), params: {
      estimate: {
        notes: "Updated estimate",
        expires_on: "2026-11-01",
        estimate_line_items_attributes: {
          "0" => {
            id: line_item.id,
            description: line_item.description,
            quantity: 2,
            unit_price: line_item.unit_price
          }
        }
      }
    }

    assert_redirected_to job_estimate_url(@job)
    assert_equal "Updated estimate", @estimate.reload.notes
    assert_equal 2, line_item.reload.quantity
  end

  test "cannot access another user's estimate" do
    get job_estimate_url(jobs(:office_buildout))

    assert_response :not_found
  end

  test "cannot create estimate for another user's job" do
    assert_no_difference("Estimate.count") do
      post job_estimate_url(jobs(:office_buildout)), params: {
        estimate: {
          notes: "Unauthorized estimate"
        }
      }
    end

    assert_response :not_found
  end
end
