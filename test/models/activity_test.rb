require "test_helper"

class ActivityTest < ActiveSupport::TestCase
  test "belongs to its trackable and optional actor" do
    activity = jobs(:kitchen_renovation).activities.create!(event: "job_status_changed", actor: users(:one))

    assert_equal jobs(:kitchen_renovation), activity.reload.trackable
    assert_equal users(:one), activity.actor
    assert_includes users(:one).activities, activity
    assert_equal({}, activity.metadata)
    assert_not_nil activity.created_at
    assert activity.update(actor: nil)
  end

  test "trackable can be another resource type" do
    activity = Activity.create!(trackable: customers(:johnson), event: "customer_updated")

    assert_equal customers(:johnson), activity.reload.trackable
  end

  test "requires a trackable and event" do
    activity = Activity.new

    assert_not activity.valid?
    assert_includes activity.errors[:trackable], "must exist"
    assert_includes activity.errors[:event], "can't be blank"
  end

  test "metadata must be a JSON object and supports historical details" do
    activity = Activity.new(trackable: jobs(:kitchen_renovation), event: "attachment_removed")

    [ nil, [], "filename" ].each do |metadata|
      activity.metadata = metadata
      assert_not activity.valid?
      assert_includes activity.errors[:metadata], "must be an object"
    end

    activity.metadata = { filename: "project.txt", attachment_id: 123 }
    activity.save!
    assert_equal({ "filename" => "project.txt", "attachment_id" => 123 }, activity.reload.metadata)
  end

  test "newest first orders by event time with stable ties" do
    job = jobs(:kitchen_renovation)
    recent = job.activities.create!(event: "recent", created_at: 1.day.ago)
    oldest = job.activities.create!(event: "oldest", created_at: 2.days.ago)
    tied = job.activities.create!(event: "tied", created_at: recent.created_at)

    assert_equal [ tied, recent, oldest ], job.activities.newest_first.to_a
  end

  test "destroying a job removes its activities and preserves other jobs history" do
    activity = jobs(:kitchen_renovation).activities.create!(event: "job_status_changed")
    other_activity = jobs(:office_buildout).activities.create!(event: "job_status_changed")

    jobs(:kitchen_renovation).destroy!

    assert_not Activity.exists?(activity.id)
    assert Activity.exists?(other_activity.id)
  end

  test "deleting an actor preserves history belonging to a different owner" do
    activity = jobs(:kitchen_renovation).activities.create!(event: "job_status_changed", actor: users(:two))

    users(:two).destroy!

    assert_nil activity.reload.actor
    assert_equal jobs(:kitchen_renovation), activity.trackable
  end
end
