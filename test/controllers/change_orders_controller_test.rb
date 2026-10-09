require "test_helper"

class ChangeOrdersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @job = jobs(:kitchen_renovation)
    @change_order = change_orders(:kitchen_lighting)
    sign_in_as users(:one)
  end

  test "index lists only the selected job's change orders" do
    second = @job.change_orders.create!(title: "Additional shelving")
    other_job = customers(:johnson).jobs.create!(name: "Bathroom Remodel")
    other_order = other_job.change_orders.create!(title: "Bathroom tile upgrade")

    get job_change_orders_url(@job)

    assert_response :success
    [@change_order, second].each do |change_order|
      assert_select "a[href=?]", job_change_order_path(@job, change_order), text: change_order.title
    end
    assert_select "body", text: /Bathroom tile upgrade|Additional conference room outlets/, count: 0
    assert_select "a[href=?]", job_change_order_path(other_job, other_order), count: 0
  end

  test "index displays an empty state" do
    job = customers(:johnson).jobs.create!(name: "Bathroom Remodel")
    get job_change_orders_url(job)

    assert_response :success
    assert_select "h2", text: "No change orders yet"
    assert_select "a[href=?]", new_job_change_order_path(job), text: "New change order", count: 1
  end

  test "job page links to change orders" do
    get job_url(@job)

    assert_select "a[href=?]", job_change_orders_path(@job), text: /View change orders/
  end

  test "new provides blank rows without lifecycle fields" do
    get new_job_change_order_url(@job)

    assert_response :success
    assert_select "form[action=?]", job_change_orders_path(@job)
    assert_select "input[name$='[quantity]']", count: 3
    assert_select "input[name$='[quantity]'][value]", count: 0
    %w[status approved_at requested_at job_id].each do |field|
      assert_select "[name=?]", "change_order[#{field}]", count: 0
    end
  end

  test "create adds another change order with line items and ignores blank rows and protected fields" do
    assert_difference("ChangeOrder.count", 1) do
      assert_difference("ChangeOrderLineItem.count", 2) do
        post job_change_orders_url(@job), params: {
          change_order: {
            title: "Additional shelving", description: "Add oak shelves",
            job_id: jobs(:office_buildout).id, status: "approved",
            approved_at: "2026-09-25", requested_at: "2026-09-25",
            change_order_line_items_attributes: {
              "0" => { description: "Shelves", quantity: 2, unit_price: "125.25" },
              "1" => { description: "Labor", quantity: "1.5", unit_price: 80 },
              "2" => { description: "", quantity: "", unit_price: "" }
            }
          }
        }
      end
    end

    change_order = @job.change_orders.find_by!(title: "Additional shelving")
    assert_redirected_to job_change_order_url(@job, change_order)
    assert_equal "draft", change_order.status
    assert_nil change_order.approved_at
    assert_nil change_order.requested_at
    assert_equal BigDecimal("370.50"), change_order.total
    assert_equal 2, @job.change_orders.count
  end

  test "show displays line items and calculated total" do
    get job_change_order_url(@job, @change_order)

    assert_response :success
    assert_select "h1", @change_order.title
    assert_select "td", text: "LED lighting kits"
    assert_select "tfoot", text: /Change order total\s+\$444\.00/
    assert_select "a[href=?]", edit_job_change_order_path(@job, @change_order)
  end

  test "every non-approved status allows edit and update" do
    %w[draft pending rejected].each do |status|
      @change_order.update!(status: status)
      get edit_job_change_order_url(@job, @change_order)

      assert_response :success
      assert_select "input[name$='[quantity]']", count: 5
      assert_select "input[type='checkbox'][name$='[_destroy]']", count: 2

      patch job_change_order_url(@job, @change_order), params: { change_order: { title: "Edited while #{status}" } }
      assert_redirected_to job_change_order_url(@job, @change_order)
      assert_equal "Edited while #{status}", @change_order.reload.title
    end
  end

  test "update edits existing items and adds new items while ignoring blank rows and protected fields" do
    item = change_order_line_items(:lighting_materials)
    assert_difference("ChangeOrderLineItem.count", 1) do
      patch job_change_order_url(@job, @change_order), params: {
        change_order: {
          title: "Revised lighting", description: "More lights",
          job_id: jobs(:office_buildout).id, status: "approved", approved_at: "2026-09-25", requested_at: "2026-09-25",
          change_order_line_items_attributes: {
            "0" => { id: item.id, description: "Updated kits", quantity: 4, unit_price: 90 },
            "1" => { description: "Dimmer", quantity: 1, unit_price: 50, change_order_id: change_orders(:office_outlets).id },
            "2" => { description: "", quantity: "", unit_price: "" }
          }
        }
      }
    end

    assert_redirected_to job_change_order_url(@job, @change_order)
    assert_equal "Revised lighting", @change_order.reload.title
    assert_equal @job, @change_order.job
    assert_equal "draft", @change_order.status
    assert_nil @change_order.approved_at
    assert_nil @change_order.requested_at
    assert_equal "Updated kits", item.reload.description
    assert_equal 4, item.quantity
    assert_equal 90, item.unit_price
    assert_equal BigDecimal("597.50"), @change_order.total
    assert @change_order.change_order_line_items.exists?(description: "Dimmer")
  end

  test "update removes existing line items" do
    item = change_order_line_items(:lighting_materials)
    assert_difference("ChangeOrderLineItem.count", -1) do
      patch job_change_order_url(@job, @change_order), params: {
        change_order: { change_order_line_items_attributes: {
          "0" => { id: item.id, _destroy: "1" },
          "1" => { description: "", quantity: "", unit_price: "" }
        } }
      }
    end

    assert_redirected_to job_change_order_url(@job, @change_order)
    assert_not ChangeOrderLineItem.exists?(item.id)
    assert_equal BigDecimal("187.50"), @change_order.reload.total
  end

  test "invalid create preserves input and renders errors and blank rows" do
    assert_no_difference(["ChangeOrder.count", "ChangeOrderLineItem.count"]) do
      post job_change_orders_url(@job), params: {
        change_order: { title: "Shelving", change_order_line_items_attributes: {
          "0" => { description: "Oak shelves", quantity: "", unit_price: 100 },
          "1" => { description: "", quantity: "", unit_price: "" }
        } }
      }
    end

    assert_response :unprocessable_entity
    assert_select "h1", "New change order"
    assert_select "li", text: /quantity is not a number/
    assert_select "input[name='change_order[title]'][value='Shelving']"
    assert_select "input[name$='[description]'][value='Oak shelves']"
    assert_select "input[name$='[quantity]']", count: 4
  end

  test "invalid update preserves input and rolls back nested changes" do
    item = change_order_line_items(:lighting_materials)
    original_title = @change_order.title
    original_quantity = item.quantity
    assert_no_difference("ChangeOrderLineItem.count") do
      patch job_change_order_url(@job, @change_order), params: {
        change_order: { title: "Unsaved title", change_order_line_items_attributes: {
          "0" => { id: item.id, quantity: 10 },
          "1" => { description: "Dimmer", quantity: "", unit_price: 50 },
          "2" => { id: change_order_line_items(:lighting_labor).id, _destroy: "1" }
        } }
      }
    end

    assert_response :unprocessable_entity
    assert_select "h1", "Edit change order"
    assert_select "li", text: /quantity is not a number/
    assert_select "input[name='change_order[title]'][value='Unsaved title']"
    assert_select "input[name$='[description]'][value='Dimmer']"
    assert_equal original_title, @change_order.reload.title
    assert_equal original_quantity, item.reload.quantity
  end

  test "approved change orders cannot be edited or updated" do
    @change_order.update!(status: "approved", approved_at: Time.current)
    original_attributes = @change_order.attributes
    original_items = @change_order.change_order_line_items.order(:id).map(&:attributes)
    original_total = @change_order.total

    get job_change_order_url(@job, @change_order)
    assert_select "a[href=?]", edit_job_change_order_path(@job, @change_order), count: 0
    get edit_job_change_order_url(@job, @change_order)
    assert_response :see_other
    assert_redirected_to job_change_order_url(@job, @change_order)

    patch job_change_order_url(@job, @change_order), params: {
      change_order: { title: "Changed", status: "draft", change_order_line_items_attributes: {
        "0" => { id: change_order_line_items(:lighting_materials).id, quantity: 99, unit_price: 1 },
        "1" => { id: change_order_line_items(:lighting_labor).id, _destroy: "1" }
      } }
    }
    assert_response :see_other
    assert_redirected_to job_change_order_url(@job, @change_order)
    assert_equal original_attributes, @change_order.reload.attributes
    assert_equal original_items, @change_order.change_order_line_items.order(:id).map(&:attributes)
    assert_equal original_total, @change_order.total
  end

  test "another user's job is inaccessible for all actions" do
    other_job = jobs(:office_buildout)
    other_order = change_orders(:office_outlets)
    original_attributes = other_order.attributes

    [job_change_orders_url(other_job), new_job_change_order_url(other_job),
      job_change_order_url(other_job, other_order), edit_job_change_order_url(other_job, other_order)].each do |url|
      get url
      assert_response :not_found
    end
    assert_no_difference("ChangeOrder.count") do
      post job_change_orders_url(other_job), params: { change_order: { title: "Unauthorized" } }
    end
    assert_response :not_found
    patch job_change_order_url(other_job, other_order), params: { change_order: { title: "Unauthorized" } }
    assert_response :not_found
    assert_equal original_attributes, other_order.reload.attributes
  end

  test "change order IDs must belong to the selected job" do
    own_other_job = customers(:johnson).jobs.create!(name: "Bathroom Remodel")
    own_other_order = own_other_job.change_orders.create!(title: "Tile upgrade")

    [change_orders(:office_outlets), own_other_order].each do |other_order|
      original_title = other_order.title
      get job_change_order_url(@job, other_order)
      assert_response :not_found
      get edit_job_change_order_url(@job, other_order)
      assert_response :not_found
      patch job_change_order_url(@job, other_order), params: { change_order: { title: "Unauthorized" } }
      assert_response :not_found
      assert_equal original_title, other_order.reload.title
    end
  end

  test "nested item IDs cannot update or remove items from another change order" do
    own_other_order = @job.change_orders.create!(title: "Shelving")
    own_other_item = own_other_order.change_order_line_items.create!(description: "Shelf", quantity: 1, unit_price: 100)

    [change_order_line_items(:office_outlets), own_other_item].each do |other_item|
      original_attributes = other_item.attributes
      [{ quantity: 99 }, { _destroy: "1" }].each do |attributes|
        patch job_change_order_url(@job, @change_order), params: {
          change_order: { change_order_line_items_attributes: { "0" => attributes.merge(id: other_item.id) } }
        }
        assert_response :not_found
        assert_equal original_attributes, other_item.reload.attributes
      end
    end
  end

  test "create cannot attach an existing foreign line item" do
    item = change_order_line_items(:office_outlets)
    original_attributes = item.attributes
    assert_no_difference(["ChangeOrder.count", "ChangeOrderLineItem.count"]) do
      post job_change_orders_url(@job), params: {
        change_order: { title: "Unauthorized", change_order_line_items_attributes: {
          "0" => { id: item.id, quantity: 99 }
        } }
      }
    end
    assert_response :not_found
    assert_equal original_attributes, item.reload.attributes
  end

  test "authentication is required" do
    sign_out
    get job_change_orders_url(@job)
    assert_redirected_to new_session_url
  end

  test "lifecycle actions support each current status and consistent approval timestamps" do
    { mark_pending: "pending", approve: "approved", reject: "rejected" }.each do |action, target_status|
      ChangeOrder::STATUSES.each do |initial_status|
        @change_order.update!(status: initial_status)
        previous_approval = @change_order.approved_at

        freeze_time do
          patch public_send("#{action}_job_change_order_url", @job, @change_order)

          assert_response :see_other
          assert_redirected_to job_change_order_url(@job, @change_order)
          assert_equal target_status, @change_order.reload.status
          if target_status == "approved"
            assert_equal previous_approval || Time.current, @change_order.approved_at
          else
            assert_nil @change_order.approved_at
          end
        end
      end
    end
  end

  test "repeated approval requests preserve the original timestamp" do
    patch approve_job_change_order_url(@job, @change_order)
    approved_at = @change_order.reload.approved_at
    assert_not_nil approved_at

    travel 1.hour do
      patch approve_job_change_order_url(@job, @change_order)
      assert_redirected_to job_change_order_url(@job, @change_order)
      assert_equal approved_at, @change_order.reload.approved_at
    end
  end

  test "pending and rejection actions allow editing an approved change order again" do
    %i[mark_pending reject].each do |action|
      @change_order.update!(status: "approved")
      patch public_send("#{action}_job_change_order_url", @job, @change_order)
      assert_redirected_to job_change_order_url(@job, @change_order)
      assert_nil @change_order.reload.approved_at

      get edit_job_change_order_url(@job, @change_order)
      assert_response :success
      patch job_change_order_url(@job, @change_order), params: { change_order: { title: "Revised after #{action}" } }
      assert_redirected_to job_change_order_url(@job, @change_order)
      assert_equal "Revised after #{action}", @change_order.reload.title
    end
  end

  test "lifecycle actions enforce both job ownership and change order membership" do
    other_job = jobs(:office_buildout)
    other_order = change_orders(:office_outlets)
    own_other_job = customers(:johnson).jobs.create!(name: "Bathroom Remodel")
    own_other_order = own_other_job.change_orders.create!(title: "Tile upgrade")

    [[other_job, other_order], [@job, other_order], [@job, own_other_order]].each do |job, change_order|
      original_attributes = change_order.attributes
      %i[mark_pending approve reject].each do |action|
        patch public_send("#{action}_job_change_order_url", job, change_order)
        assert_response :not_found
        assert_equal original_attributes, change_order.reload.attributes
      end
    end
  end

  test "show provides lifecycle buttons and edit excludes lifecycle fields" do
    get job_change_order_url(@job, @change_order)
    assert_response :success
    %i[mark_pending approve reject].each do |action|
      assert_select "form[action=?]", public_send("#{action}_job_change_order_path", @job, @change_order) do
        assert_select "input[name='_method'][value='patch']"
        assert_select "button", count: 1
      end
    end

    get edit_job_change_order_url(@job, @change_order)
    assert_response :success
    %w[status approved_at requested_at].each do |field|
      assert_select "[name=?]", "change_order[#{field}]", count: 0
    end
  end

  test "lifecycle actions require authentication" do
    sign_out
    %i[mark_pending approve reject].each do |action|
      patch public_send("#{action}_job_change_order_url", @job, @change_order)
      assert_redirected_to new_session_url
      assert_equal "draft", @change_order.reload.status
      assert_nil @change_order.approved_at
    end
  end
end
