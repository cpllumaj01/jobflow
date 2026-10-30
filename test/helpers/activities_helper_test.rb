require "test_helper"

class ActivitiesHelperTest < ActionView::TestCase
  test "event names are humanized without registering event types" do
    {
      "job_status_changed" => "Job status changed",
      "estimate_created" => "Estimate created",
      "estimate_status_changed" => "Estimate status changed",
      "change_order_created" => "Change order created",
      "change_order_status_changed" => "Change order status changed",
      "attachment_added" => "Attachment added",
      "attachment_removed" => "Attachment removed",
      "customer_updated" => "Customer updated"
    }.each do |event, name|
      assert_equal name, activity_event_name(Activity.new(event: event))
    end
  end

  test "missing and blank event names have a fallback" do
    [ nil, "", " " ].each do |event|
      assert_equal "Activity recorded", activity_event_name(Activity.new(event: event))
    end
  end

  test "missing or invalid metadata is treated as empty" do
    [ nil, [], "invalid", {} ].each do |metadata|
      assert_empty activity_metadata(Activity.new(metadata: metadata))
    end
  end

  test "metadata uses the configured Rails filters without modifying recorded values" do
    activity = Activity.new(metadata: {
      password: "private password", details: { access_token: "private token", count: 2 },
      items: [ { secret: "private secret", name: "Public name" } ],
      filename: "secret_contract.pdf", contact: "person@example.com"
    })
    original = activity.metadata.deep_dup

    assert_equal({
      "password" => "[FILTERED]", "details" => { "access_token" => "[FILTERED]", "count" => 2 },
      "items" => [ { "secret" => "[FILTERED]", "name" => "Public name" } ],
      "filename" => "secret_contract.pdf", "contact" => "person@example.com"
    }, activity_metadata(activity))
    assert_equal original, activity.metadata
  end

  test "string values are preserved including filenames emails URLs and long text" do
    [ "contract_v2.PDF", "Person.Name@example.com", "https://example.com/my_file?q=A_B",
      "in_progress", "Line one\nLine two", "  Keep spacing  ", "雪 & #{'long' * 500}" ].each do |value|
      assert_equal value, activity_metadata_value(value)
    end
  end

  test "numbers booleans and blank values are formatted consistently" do
    { 123 => "123", 0 => "0", 12.5 => "12.5", true => "Yes", false => "No",
      nil => "—", "" => "—", " " => "—" }.each do |value, expected|
      assert_equal expected, activity_metadata_value(value)
    end
  end

  test "arrays and nested objects are formatted as readable JSON" do
    [ [ "contract_v2.pdf", 123, true, nil ],
      { "details" => { "count" => 2, "ready" => false }, "items" => [ "one", "two" ] },
      [], {} ].each do |value|
      assert_equal value, JSON.parse(activity_metadata_value(value))
    end
    assert_includes activity_metadata_value({ "count" => 2 }), "\n"
  end

  test "business values are formatted only for their specific metadata keys" do
    assert_equal "$1,234.57", activity_metadata_value("1234.567", "total")
    assert_equal "$0.00", activity_metadata_value(0, "total")
    assert_equal "-$50.25", activity_metadata_value("-50.25", "total")
    assert_equal "In progress", activity_metadata_value("in_progress", "new_status")
    assert_equal "Draft", activity_metadata_value("draft", "previous_status")
    assert_equal "1 line item", activity_metadata_value(1, "line_item_count")
    assert_equal "2 line items", activity_metadata_value(2, "line_item_count")
    assert_equal "0 line items", activity_metadata_value(0, "line_item_count")
    [ nil, "unknown", { "amount" => 10 }, [ 1, 2 ], false ].each do |value|
      %w[total line_item_count].each do |key|
        assert_equal activity_metadata_value(value), activity_metadata_value(value, key)
      end
    end
    assert_equal "1234.567", activity_metadata_value("1234.567", "reference")
  end

  test "known timestamp metadata uses the application time zone and preserves the instant" do
    %w[completed_at previous_completed_at].each do |key|
      Time.use_zone("UTC") do
        assert_equal "Oct 30, 2026 at 1:52 PM UTC", activity_metadata_value("2026-10-30T13:52:11.955001Z", key)
        assert_equal "Oct 30, 2026 at 1:52 PM UTC", activity_metadata_value("2026-10-30T09:52:11.955001-04:00", key)
      end
      Time.use_zone("America/New_York") do
        assert_equal "Oct 30, 2026 at 9:52 AM EDT", activity_metadata_value("2026-10-30T13:52:11.955001Z", key)
        assert_equal "Dec 31, 2025 at 9:15 PM EST", activity_metadata_value("2026-01-01T02:15:00Z", key)
      end
    end
  end

  test "invalid timestamps and unrelated metadata retain generic rendering" do
    %w[completed_at previous_completed_at].each do |key|
      [ nil, "", " ", "invalid", "tomorrow", "2026-13-45T99:99:99Z", "[FILTERED]",
        "<script>alert(1)</script>", 123, false, [ "2026-10-30T13:52:11Z" ], { "value" => "invalid" } ].each do |value|
        assert_equal activity_metadata_value(value), activity_metadata_value(value, key)
      end
    end
    timestamp = "2026-10-30T13:52:11.955001Z"
    [ nil, "filename", "notes", "custom_at" ].each do |key|
      assert_equal timestamp, activity_metadata_value(timestamp, key)
    end
  end

  test "timeline timestamps share formatting without changing stored metadata or filtering" do
    activity = jobs(:kitchen_renovation).activities.create!(event: "job_status_changed",
      created_at: "2026-10-30T13:52:11.955001Z", metadata: {
        completed_at: "2026-10-30T13:52:11.955001Z", previous_completed_at: "2026-01-01T02:15:00Z",
        details: { access_token: "private token" }
      })
    original = activity.reload.attributes.deep_dup

    Time.use_zone("America/New_York") do
      render partial: "activities/activity", locals: { activity: activity }
    end

    assert_select "time[datetime=?]", activity.created_at.iso8601, text: "Oct 30, 2026 at 9:52 AM EDT"
    assert_select "dt", text: "Completed at"
    assert_select "dd", text: "Oct 30, 2026 at 9:52 AM EDT"
    assert_select "dt", text: "Previous completed at"
    assert_select "dd", text: "Dec 31, 2025 at 9:15 PM EST"
    assert_select "dd", text: /\[FILTERED\]/
    assert_select "li", text: /private token/, count: 0
    assert_equal original, activity.reload.attributes
  end

  test "partial renders arbitrary labels and values and escapes all metadata" do
    long_value = "<script>alert('value')</script>#{'unbroken' * 100}"
    activity = Activity.new(trackable: customers(:johnson), event: "customer_updated", created_at: Time.current,
      metadata: { contract_value: 123, external_id: 45, confirmed: false, missing: nil,
        "<img src=x onerror=alert(1)>" => long_value, details: { "text" => "<script>nested</script>" } })

    render partial: "activities/activity", locals: { activity: activity }

    assert_select "li p", text: "Customer updated"
    assert_select "dt", text: "Contract value"
    assert_select "dt", text: "External id"
    assert_select "dd", text: "123"
    assert_select "dd", text: "45"
    assert_select "dd", text: "No"
    assert_select "dd", text: "—"
    assert_select "dd", text: long_value
    assert_select "dd", text: /<script>nested<\/script>/
    assert_select "dt", text: /<img/
    assert_select "script, img", count: 0
  end

  test "partial omits empty metadata containers and tolerates a deleted actor" do
    activity = Activity.create!(trackable: customers(:johnson), actor: users(:two),
      event: "customer_updated", metadata: {})
    users(:two).destroy!

    render partial: "activities/activity", locals: { activity: activity.reload }

    assert_select "li p", text: "Customer updated"
    assert_select "dl", count: 0
    assert_select "span", count: 0
    assert_select "time[datetime=?]", activity.created_at.iso8601,
      text: activity.created_at.strftime("%b %-d, %Y at %-I:%M %p %Z")
  end

  test "business descriptions and promoted details remain escaped and filtered" do
    activity = Activity.new(event: "change_order_status_changed", actor: users(:one), created_at: Time.current,
      metadata: { previous_status: "draft", new_status: "<script>alert(1)</script>",
        title: "<img src=x onerror=alert(1)>", filename: "secret_contract.pdf",
        completed_at: "<script>timestamp</script>",
        total: "<script>amount</script>", details: { password: "private password", access_token: "private token" } })

    render partial: "activities/activity", locals: { activity: activity }

    assert_select "p", text: /Change order changed from Draft to <script>/
    assert_select "p", text: "<img src=x onerror=alert(1)>"
    assert_select "p", text: "secret_contract.pdf"
    assert_select "dd", text: "<script>amount</script>"
    assert_select "dd", text: "<script>timestamp</script>"
    assert_select "dd", text: /\[FILTERED\]/
    assert_select "li", text: /private password|private token/, count: 0
    assert_select "script, img", count: 0
  end
end
