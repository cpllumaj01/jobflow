require "test_helper"

class JobActivityTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @job = jobs(:kitchen_renovation)
    @estimate = estimates(:kitchen_estimate)
    @change_order = change_orders(:kitchen_lighting)
    sign_in_as @user
  end

  test "job status changes record the actor and transition only once" do
    Job::STATUSES.each do |status|
      previous_status = @job.reload.status
      previous_completion = @job.completed_at
      assert_difference("Activity.count", 1) do
        patch job_url(@job), params: { job: {
          customer_id: @job.customer_id, status: status, actor_id: users(:two).id,
          trackable_id: jobs(:office_buildout).id, metadata: { new_status: "forged" }
        } }
      end

      assert_redirected_to job_url(@job)
      activity = @job.activities.newest_first.first
      assert_equal @user, activity.actor
      assert_equal "job_status_changed", activity.event
      expected = { "previous_status" => previous_status, "new_status" => status }
      expected["completed_at"] = @job.reload.completed_at.iso8601(6) if status == "completed"
      expected["previous_completed_at"] = previous_completion.iso8601(6) if previous_status == "completed"
      assert_equal expected, activity.metadata

      assert_no_difference("Activity.count") do
        patch job_url(@job), params: { job: { customer_id: @job.customer_id, status: status, description: "Updated details" } }
      end
      assert_redirected_to job_url(@job)
    end
  end

  test "invalid job updates and foreign customers or jobs do not record activities" do
    original_status = @job.status
    assert_no_difference("Activity.count") do
      patch job_url(@job), params: { job: { customer_id: @job.customer_id, name: "", status: "completed" } }
      assert_response :unprocessable_entity
      assert_equal original_status, @job.reload.status

      patch job_url(@job), params: { job: { customer_id: @job.customer_id, status: "unknown" } }
      assert_response :unprocessable_entity

      patch job_url(@job), params: { job: { customer_id: customers(:fairfield).id, status: "completed" } }
      assert_response :not_found

      patch job_url(jobs(:office_buildout)), params: { job: { customer_id: @job.customer_id, status: "completed" } }
      assert_response :not_found
    end
    assert_equal original_status, @job.reload.status
  end

  test "failed lifecycle operations do not record activities or change statuses" do
    [ [ @estimate, approve_job_estimate_url(@job) ],
      [ @change_order, approve_job_change_order_url(@job, @change_order) ] ].each do |record, url|
      record.update!(status: "draft")
      failure = ->(model) { model.errors.add(:base, "Cannot approve"); throw :abort }
      begin
        record.class.set_callback(:update, :before, failure)
        assert_no_difference("Activity.count") { patch url }
        assert_response :unprocessable_entity
        assert_equal "draft", record.reload.status
      ensure
        record.class.skip_callback(:update, :before, failure)
      end
    end
  end

  test "ordinary estimate and change order edits do not record activities" do
    @estimate.update!(status: "draft")
    assert_no_difference("Activity.count") do
      patch job_estimate_url(@job), params: { estimate: { notes: "Clarify materials" } }
      assert_redirected_to job_estimate_url(@job)
      patch job_change_order_url(@job, @change_order), params: { change_order: { title: "Revised lighting" } }
      assert_redirected_to job_change_order_url(@job, @change_order)
    end
  end

  test "creation and lifecycle snapshots retain only business details after edits and deletion" do
    job = customers(:johnson).jobs.create!(name: "Deck")
    post job_estimate_url(job), params: { estimate: {
      notes: "Private proposal notes", estimate_line_items_attributes: [ { description: "Labor", quantity: "1.5", unit_price: "100.25" } ]
    } }
    assert_response :redirect
    post job_change_orders_url(job), params: { change_order: {
      title: "Add stairs", description: "Private scope notes",
      change_order_line_items_attributes: [ { description: "Materials", quantity: "2", unit_price: "75.25" } ]
    } }
    assert_response :redirect
    estimate = job.estimate
    change_order = job.change_orders.sole
    created = job.activities.order(:id).to_a
    originals = created.map { |activity| activity.metadata.deep_dup }
    assert_equal [ "150.375", "150.5" ], originals.map { |metadata| metadata["total"] }
    assert_equal [ 1, 1 ], originals.map { |metadata| metadata["line_item_count"] }
    assert_equal [ "draft", "draft" ], originals.map { |metadata| metadata["new_status"] }
    assert_equal "Add stairs", originals.last["title"]
    assert_equal %w[estimate_id new_status total line_item_count].sort, originals.first.keys.sort
    assert_equal %w[change_order_id title new_status total line_item_count].sort, originals.last.keys.sort

    estimate.estimate_line_items.sole.update!(quantity: 4)
    change_order.update!(title: "Revised stairs")
    change_order.change_order_line_items.create!(description: "Labor", quantity: 1, unit_price: 50)
    assert_difference("Activity.count", 2) do
      patch mark_sent_job_estimate_url(job)
      patch mark_pending_job_change_order_url(job, change_order)
    end
    transitions = job.activities.order(:id).last(2)
    snapshots = transitions.map { |activity| activity.metadata.deep_dup }
    assert_equal [ "401.0", "200.5" ], snapshots.map { |metadata| metadata["total"] }
    assert_equal [ 1, 2 ], snapshots.map { |metadata| metadata["line_item_count"] }
    assert_equal "Revised stairs", snapshots.last["title"]
    assert_equal [ "draft", "draft" ], snapshots.map { |metadata| metadata["previous_status"] }
    assert_equal [ "sent", "pending" ], snapshots.map { |metadata| metadata["new_status"] }

    estimate.destroy!
    change_order.destroy!
    assert_equal originals, created.map { |activity| activity.reload.metadata }
    assert_equal snapshots, transitions.map { |activity| activity.reload.metadata }
    get job_url(job)
    assert_response :success
    assert_select "section[aria-labelledby='activity-heading']" do
      assert_select "p", text: "Add stairs"
      assert_select "p", text: "Revised stairs"
      %w[$150.38 $150.50 $401.00 $200.50].each { |total| assert_select "dd", text: total }
      assert_select "li", text: /Private|Materials|Labor/, count: 0
    end
  end

  test "activity producing actions require authentication" do
    sign_out

    assert_no_difference([ "Activity.count", "Estimate.count", "ChangeOrder.count", "ActiveStorage::Attachment.count" ]) do
      patch job_url(@job), params: { job: { customer_id: @job.customer_id, status: "completed" } }
      assert_redirected_to new_session_url
      [ mark_sent_job_estimate_url(@job), approve_job_estimate_url(@job), reject_job_estimate_url(@job),
        mark_pending_job_change_order_url(@job, @change_order), approve_job_change_order_url(@job, @change_order),
        reject_job_change_order_url(@job, @change_order) ].each do |url|
        patch url
        assert_redirected_to new_session_url
      end
      post job_estimate_url(@job), params: { estimate: { notes: "Unauthorized" } }
      assert_redirected_to new_session_url
      post job_change_orders_url(@job), params: { change_order: { title: "Unauthorized" } }
      assert_redirected_to new_session_url
    end
  end

  test "status updates roll back when activity creation fails" do
    @estimate.update!(status: "draft")
    original_job_status = @job.status

    with_failed_activity_creation do
      assert_no_difference("Activity.count") do
        assert_raises(IOError) do
          patch job_url(@job), params: { job: { customer_id: @job.customer_id, status: "completed", name: "Unsaved name" } }
        end
        assert_raises(IOError) { patch approve_job_estimate_url(@job) }
        assert_raises(IOError) { patch approve_job_change_order_url(@job, @change_order) }
      end
    end

    assert_equal original_job_status, @job.reload.status
    assert_equal "Kitchen Renovation", @job.name
    assert_nil @job.completed_at
    assert_equal "draft", @estimate.reload.status
    assert_nil @estimate.approved_at
    assert_equal "draft", @change_order.reload.status
    assert_nil @change_order.approved_at
  end

  test "quick status changes and completion timestamps roll back when history cannot be saved" do
    with_failed_activity_creation do
      assert_no_difference("Activity.count") do
        assert_raises(IOError) do
          patch update_status_job_url(@job), params: { job: { status: "completed" } }
        end
      end
    end

    assert_equal "in_progress", @job.reload.status
    assert_nil @job.completed_at
  end

  test "estimate and change order creation roll back when activity creation fails" do
    job = customers(:johnson).jobs.create!(name: "Deck")

    with_failed_activity_creation do
      assert_no_difference([ "Activity.count", "Estimate.count", "EstimateLineItem.count", "ChangeOrder.count", "ChangeOrderLineItem.count" ]) do
        assert_raises(IOError) do
          post job_estimate_url(job), params: { estimate: {
            notes: "Proposal", estimate_line_items_attributes: [ { description: "Labor", quantity: 1, unit_price: 100 } ]
          } }
        end
        assert_raises(IOError) do
          post job_change_orders_url(job), params: { change_order: {
            title: "Lighting", change_order_line_items_attributes: [ { description: "Labor", quantity: 1, unit_price: 100 } ]
          } }
        end
      end
    end
  end

  test "attachment changes roll back without purging storage when activity creation fails" do
    @job.files.attach(fixture_file_upload("project.txt", "text/plain"))
    attachment = @job.files.first
    blob = attachment.blob

    with_failed_activity_creation do
      assert_no_difference([ "Activity.count", "ActiveStorage::Attachment.count", "ActiveStorage::Blob.count" ]) do
        assert_raises(IOError) do
          post job_attachments_url(@job), params: { job: { files: [ fixture_file_upload("project.txt", "text/plain") ] } }
        end
        assert_raises(IOError) { delete job_attachment_url(@job, attachment) }
      end
    end

    assert_equal [ attachment.id ], @job.reload.files.ids
    assert blob.service.exist?(blob.key)
    assert_equal File.read(file_fixture("project.txt")), @job.files.first.download
  end

  test "timeline preserves recorded metadata after related resources are removed" do
    @estimate.update!(status: "draft")
    patch mark_sent_job_estimate_url(@job)
    patch approve_job_estimate_url(@job)
    patch reject_job_estimate_url(@job)
    patch mark_pending_job_change_order_url(@job, @change_order)
    patch approve_job_change_order_url(@job, @change_order)
    patch reject_job_change_order_url(@job, @change_order)
    post job_attachments_url(@job), params: { job: { files: [ fixture_file_upload("project.txt", "text/plain") ] } }
    delete job_attachment_url(@job, @job.files.first)
    @estimate.destroy!
    @change_order.update!(title: "Renamed later")
    @change_order.destroy!

    get job_url(@job)

    assert_response :success
    assert_select "section[aria-labelledby='activity-heading']" do
      assert_select "li", count: 8
      [ "Draft to Sent", "Sent to Approved", "Approved to Rejected" ].each do |transition|
        assert_select "p", text: "Estimate changed from #{transition}"
      end
      [ "Draft to Pending", "Pending to Approved", "Approved to Rejected" ].each do |transition|
        assert_select "p", text: "Change order changed from #{transition}"
      end
      assert_select "p", text: "Add under-cabinet lighting", count: 3
      assert_select "dd", text: "$27,000.00", count: 3
      assert_select "dd", text: "$444.00", count: 3
      assert_select "p", text: "Attachment added"
      assert_select "p", text: "Attachment removed"
      assert_select "p", text: "project.txt", count: 2
      assert_select "li", text: /Renamed later/, count: 0
      assert_select "dt", text: /Estimate id|Change order id|Attachment id/, count: 0
      assert_select "span", text: @user.email_address, count: 8
    end
  end

  test "timeline renders newest first with stable ties actors timestamps and escaped details" do
    oldest = @job.activities.create!(event: "job_status_changed", actor: @user, created_at: 2.days.ago,
      metadata: { previous_status: "quoted", new_status: "in_progress" })
    recent = @job.activities.create!(event: "estimate_created", created_at: 1.day.ago,
      metadata: { estimate_id: 123, new_status: "draft" })
    @job.activities.create!(event: "change_order_created", actor: @user, created_at: recent.created_at,
      metadata: { title: "<script>alert('change')</script>", new_status: "draft" })
    jobs(:office_buildout).activities.create!(event: "attachment_added", metadata: { filename: "private.txt" })

    get job_url(@job)

    assert_response :success
    assert_select "section[aria-labelledby='activity-heading']" do
      assert_select "li > div > p:first-child" do |events|
        assert_equal [ "Change order created", "Estimate created", "Job changed from Quoted to In progress" ], events.map(&:text)
      end
      assert_select "p", text: "<script>alert('change')</script>"
      assert_select "dt", text: "Status", count: 2
      assert_select "dd", text: "Draft", count: 2
      assert_select "span", text: @user.email_address, count: 2
      assert_select "time[datetime=?]", oldest.created_at.iso8601,
        text: oldest.created_at.strftime("%b %-d, %Y at %-I:%M %p %Z")
      assert_select "script", count: 0
      assert_select "li", text: /private.txt/, count: 0
    end

    get job_url(jobs(:office_buildout))
    assert_response :not_found
    sign_out
    get job_url(@job)
    assert_redirected_to new_session_url
  end

  test "timeline safely renders incomplete and legacy metadata without looking up current values" do
    @job.activities.create!(event: "job_status_changed", metadata: { previous_status: "quoted" })
    @job.activities.create!(event: "estimate_status_changed", metadata: { estimate_id: 123, new_status: nil })
    @job.activities.create!(event: "change_order_status_changed", metadata: { new_status: "approved" })
    @job.activities.create!(event: "attachment_removed")
    @job.activities.create!(event: "custom_event")

    get job_url(@job)

    assert_response :success
    assert_select "section[aria-labelledby='activity-heading']" do
      assert_select "p", text: "Job status changed"
      assert_select "p", text: "Estimate status changed"
      assert_select "p", text: "Change order marked as Approved"
      assert_select "p", text: "Attachment removed"
      assert_select "p", text: "Custom event"
      assert_select "dt", text: "Previous status"
      assert_select "dd", text: "Quoted"
      assert_select "dt", text: "Estimate id", count: 0
      assert_select "dd", text: "123", count: 0
      assert_select "dt", text: "Total", count: 0
      assert_select "dd", text: "—"
      assert_select "li", text: /Attachment removed|Custom event/ do
        assert_select "dl", count: 0
      end
      assert_select "p", text: /→/, count: 0
    end
  end

  test "timeline renders a new event and arbitrary metadata without changing recorded activity" do
    activity = @job.activities.create!(event: "site_visit_scheduled", actor: @user, metadata: {
      location: "Workshop", attendees: [ "Pat", "Jo" ], confirmed: true, contract_value: 2500,
      details: { access_token: "private token", instructions: "Use side door" }
    })

    assert_no_changes -> { activity.reload.attributes } do
      assert_no_difference("Activity.count") { get job_url(@job) }
    end

    assert_response :success
    assert_select "section[aria-labelledby='activity-heading']" do
      assert_select "p", text: "Site visit scheduled"
      assert_select "dt", text: "Location"
      assert_select "dd", text: "Workshop"
      assert_select "dt", text: "Confirmed"
      assert_select "dd", text: "Yes"
      assert_select "dt", text: "Contract value"
      assert_select "dd", text: "2500"
      assert_select "dt", text: "Attendees"
      assert_select "dd", text: /Pat.*Jo/m
      assert_select "dd", text: /\[FILTERED\].*Use side door/m
      assert_select "li", text: /private token/, count: 0
    end
  end

  test "timeline has an empty state without recording reads" do
    assert_no_difference("Activity.count") { get job_url(@job) }

    assert_select "section[aria-labelledby='activity-heading']" do
      assert_select "h2", "Activity"
      assert_select "p", "No activity yet. Status changes, estimates, change orders, and attachments will appear here."
      assert_select "li", count: 0
    end
  end

  private
    def with_failed_activity_creation
      failure = -> { raise IOError, "History unavailable" }
      Activity.set_callback(:create, :before, failure)
      yield
    ensure
      Activity.skip_callback(:create, :before, failure)
    end
end
