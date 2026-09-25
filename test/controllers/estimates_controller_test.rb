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
    assert_select "input[name$='[description]']", count: 3
    assert_select "input[name$='[quantity]'][value]", count: 0
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
            },
            "1" => { description: "", quantity: "", unit_price: "" }
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

  test "invalid create preserves line items and provides blank rows" do
    job = customers(:johnson).jobs.create!(name: "Deck Replacement")

    assert_no_difference(["Estimate.count", "EstimateLineItem.count"]) do
      post job_estimate_url(job), params: {
        estimate: { estimate_line_items_attributes: {
          "0" => { description: "Lumber", quantity: 2, unit_price: "" },
          "1" => { description: "", quantity: "", unit_price: "" }
        } }
      }
    end

    assert_response :unprocessable_entity
    assert_select "input[name$='[description]'][value='Lumber']"
    assert_select "input[name$='[description]']", count: 4
  end

  test "should get edit" do
    get edit_job_estimate_url(@job)

    assert_response :success
    assert_select "input[name$='[description]']", count: 6
    assert_select "input[type='checkbox'][name$='[_destroy]']", count: 3
  end

  test "update adds line items and ignores unused rows" do
    assert_difference("EstimateLineItem.count", 2) do
      patch job_estimate_url(@job), params: {
        estimate: { estimate_line_items_attributes: {
          "0" => { description: "Paint", quantity: 2, unit_price: 25 },
          "1" => { description: "Trim", quantity: 3, unit_price: 10 },
          "2" => { description: "", quantity: "", unit_price: "" }
        } }
      }
    end

    assert_redirected_to job_estimate_url(@job)
    assert_equal 27_080, @estimate.reload.total
  end

  test "update removes existing line items while ignoring blank rows" do
    line_item = estimate_line_items(:cabinets)

    assert_difference("EstimateLineItem.count", -1) do
      patch job_estimate_url(@job), params: {
        estimate: { estimate_line_items_attributes: {
          "0" => { id: line_item.id, _destroy: "1" },
          "1" => { description: "", quantity: "", unit_price: "" }
        } }
      }
    end

    assert_redirected_to job_estimate_url(@job)
    assert_not EstimateLineItem.exists?(line_item.id)
  end

  test "invalid new line item preserves input without saving other changes" do
    assert_no_difference("EstimateLineItem.count") do
      patch job_estimate_url(@job), params: {
        estimate: { notes: "Unsaved notes", estimate_line_items_attributes: {
          "0" => { description: "Paint", quantity: "", unit_price: 25 },
          "1" => { description: "", quantity: "", unit_price: "" }
        } }
      }
    end

    assert_response :unprocessable_entity
    assert_select "input[name$='[description]'][value='Paint']"
    assert_select "textarea", text: "Unsaved notes"
    assert_not_equal "Unsaved notes", @estimate.reload.notes
  end

  test "cannot update a line item belonging to another user's estimate" do
    other_estimate = jobs(:office_buildout).create_estimate!
    other_item = other_estimate.estimate_line_items.create!(description: "Private work", quantity: 1, unit_price: 100)

    patch job_estimate_url(@job), params: {
      estimate: { estimate_line_items_attributes: {
        "0" => { id: other_item.id, description: "Changed" }
      } }
    }

    assert_response :not_found
    assert_equal "Private work", other_item.reload.description
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
