require "test_helper"

class EstimatesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @job = jobs(:kitchen_renovation)
    @estimate = estimates(:kitchen_estimate)
    @estimate.update!(status: "draft")

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

  test "lifecycle actions support each current status and keep timestamps consistent" do
    { mark_sent: "sent", approve: "approved", reject: "rejected" }.each do |action, target_status|
      Estimate::STATUSES.each do |initial_status|
        @estimate.update!(status: initial_status)
        previous_approval = @estimate.approved_at

        freeze_time do
          patch public_send("#{action}_job_estimate_url", @job)

          assert_response :see_other
          assert_redirected_to job_estimate_url(@job)
          assert_equal target_status, @estimate.reload.status
          if target_status == "approved"
            assert_equal previous_approval || Time.current, @estimate.approved_at
          else
            assert_nil @estimate.approved_at
          end
        end
      end
    end
  end

  test "repeated approval preserves the original timestamp after time passes" do
    @estimate.update!(status: "sent")
    patch approve_job_estimate_url(@job)
    original_approval = @estimate.reload.approved_at
    assert_not_nil original_approval

    travel 1.hour do
      patch approve_job_estimate_url(@job)

      assert_redirected_to job_estimate_url(@job)
      assert_equal "approved", @estimate.reload.status
      assert_equal original_approval, @estimate.approved_at
    end
  end

  test "lifecycle actions ignore submitted estimate and ownership IDs" do
    other_job = jobs(:office_buildout)
    other_estimate = other_job.create_estimate!
    original_attributes = other_estimate.attributes

    %i[mark_sent approve reject].each do |action|
      patch public_send("#{action}_job_estimate_url", @job), params: {
        id: other_estimate.id,
        estimate: { id: other_estimate.id, job_id: other_job.id, approved_at: "2000-01-01" }
      }

      assert_redirected_to job_estimate_url(@job)
      assert_equal original_attributes, other_estimate.reload.attributes
      assert_equal @job.id, @estimate.reload.job_id
    end
  end

  test "lifecycle actions cannot access another user's estimate" do
    other_job = jobs(:office_buildout)
    other_estimate = other_job.create_estimate!

    %i[mark_sent approve reject].each do |action|
      patch public_send("#{action}_job_estimate_url", other_job)

      assert_response :not_found
      assert_equal "draft", other_estimate.reload.status
      assert_nil other_estimate.approved_at
    end
  end

  test "lifecycle actions return not found for a job without an estimate" do
    job = customers(:johnson).jobs.create!(name: "Bathroom Remodel")

    %i[mark_sent approve reject].each do |action|
      patch public_send("#{action}_job_estimate_url", job)
      assert_response :not_found
    end
    assert_nil job.reload.estimate
  end

  test "generic create cannot set lifecycle fields" do
    job = customers(:johnson).jobs.create!(name: "Bathroom Remodel")
    post job_estimate_url(job), params: {
      estimate: { notes: "New estimate", status: "approved", approved_at: Time.current }
    }

    assert_redirected_to job_estimate_url(job)
    assert_equal "draft", job.reload.estimate.status
    assert_nil job.estimate.approved_at
  end

  test "generic update cannot change lifecycle fields" do
    patch job_estimate_url(@job), params: {
      estimate: { notes: "Updated notes", status: "approved", approved_at: "2000-01-01" }
    }

    assert_redirected_to job_estimate_url(@job)
    assert_equal "draft", @estimate.reload.status
    assert_nil @estimate.approved_at
    assert_equal "Updated notes", @estimate.notes
  end

  test "show provides lifecycle buttons appropriate to the current status" do
    {
      "draft" => %i[mark_sent],
      "sent" => %i[approve reject],
      "approved" => %i[mark_sent reject],
      "rejected" => %i[mark_sent]
    }.each do |status, actions|
      @estimate.update!(status: status)
      get job_estimate_url(@job)

      assert_response :success
      %i[mark_sent approve reject].each do |action|
        path = public_send("#{action}_job_estimate_path", @job)
        if actions.include?(action)
          assert_select "form[action=?]", path, count: 1 do
            assert_select "input[name='_method'][value='patch']"
            assert_select "button", count: 1
          end
        else
          assert_select "form[action=?]", path, count: 0
        end
      end
    end
  end

  test "edit excludes lifecycle fields" do
    get edit_job_estimate_url(@job)
    assert_select "[name='estimate[status]']", count: 0
    assert_select "[name='estimate[approved_at]']", count: 0
  end

  test "approved estimate hides edit link and blocks direct edit access" do
    @estimate.update!(status: "approved")

    get job_estimate_url(@job)
    assert_response :success
    assert_select "a[href=?]", edit_job_estimate_path(@job), count: 0
    assert_select "body", text: /This estimate is approved and locked from editing/

    get edit_job_estimate_url(@job)
    assert_response :see_other
    assert_redirected_to job_estimate_url(@job)
    follow_redirect!
    assert_select "body", text: /Approved estimates cannot be edited/
  end

  test "approved estimate update cannot change estimate or line items" do
    @estimate.update!(status: "approved")
    original_attributes = @estimate.attributes
    original_items = @estimate.estimate_line_items.order(:id).map(&:attributes)
    original_total = @estimate.total

    assert_no_difference("EstimateLineItem.count") do
      patch job_estimate_url(@job), params: {
        estimate: {
          notes: "Changed", status: "draft", approved_at: "",
          estimate_line_items_attributes: {
            "0" => { id: estimate_line_items(:cabinets).id, quantity: 99, unit_price: 1 },
            "1" => { id: estimate_line_items(:labor).id, _destroy: "1" },
            "2" => { description: "Extra work", quantity: 1, unit_price: 500 }
          }
        }
      }
    end

    assert_response :see_other
    assert_redirected_to job_estimate_url(@job)
    assert_equal original_attributes, @estimate.reload.attributes
    assert_equal original_items, @estimate.estimate_line_items.order(:id).map(&:attributes)
    assert_equal original_total, @estimate.total
  end

  test "every non-approved status allows editing and updating" do
    %w[draft sent rejected].each do |status|
      @estimate.update!(status: status)

      get job_estimate_url(@job)
      assert_select "a[href=?]", edit_job_estimate_path(@job), text: "Edit estimate"
      get edit_job_estimate_url(@job)
      assert_response :success

      patch job_estimate_url(@job), params: { estimate: { notes: "Edited while #{status}" } }
      assert_redirected_to job_estimate_url(@job)
      assert_equal "Edited while #{status}", @estimate.reload.notes
    end
  end

  test "moving approved estimate to sent allows editing again" do
    @estimate.update!(status: "approved")

    patch mark_sent_job_estimate_url(@job)
    assert_redirected_to job_estimate_url(@job)
    assert_nil @estimate.reload.approved_at

    get edit_job_estimate_url(@job)
    assert_response :success
    patch job_estimate_url(@job), params: { estimate: { notes: "Revised estimate" } }
    assert_redirected_to job_estimate_url(@job)
    assert_equal "Revised estimate", @estimate.reload.notes
  end

  test "show displays all line items with currency prices and totals" do
    get job_estimate_url(@job)

    assert_response :success
    assert_select "tbody tr", count: 3
    {
      "Kitchen cabinets" => ["1.0", "$12,000.00", "$12,000.00"],
      "Quartz countertops" => ["50.0", "$150.00", "$7,500.00"],
      "Installation labor" => ["100.0", "$75.00", "$7,500.00"]
    }.each do |description, values|
      assert_select "tbody tr" do |rows|
        row = rows.find { |element| element.at_css("td").text.strip == description }
        assert_not_nil row
        assert_equal [description, *values], row.css("td").map { |cell| cell.text.strip }
      end
    end
    assert_select "th", "Line total"
    assert_select "tfoot td", text: "$27,000.00"
    assert_select "a[href=?]", edit_job_estimate_path(@job), text: "Edit estimate"
  end

  test "show displays status expiration and notes" do
    get job_estimate_url(@job)

    assert_response :success
    assert_select "dd", "Draft"
    assert_select "dd", @estimate.expires_on.to_fs(:long)
    assert_select "dd", @estimate.notes
  end

  test "show handles missing optional details and no line items" do
    @estimate.update!(expires_on: nil, notes: nil)
    @estimate.estimate_line_items.destroy_all

    get job_estimate_url(@job)

    assert_response :success
    assert_select "dd", "No expiration date"
    assert_select "dd", "No notes"
    assert_select "tbody td[colspan='4']", "No line items yet."
    assert_select "tfoot td", text: "$0.00"
    assert_select "a[href=?]", edit_job_estimate_path(@job), text: "Edit estimate"
  end
end
