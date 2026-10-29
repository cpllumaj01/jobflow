require "test_helper"

class JobStatusConcurrencyTest < ActionDispatch::IntegrationTest
  self.use_transactional_tests = false

  setup do
    @user = User.create!(email_address: "concurrent-job-status@example.com", password: "concurrency-test-password")
    @job = @user.customers.create!(name: "Customer").jobs.create!(name: "Job", status: "in_progress")
  end

  teardown { @user&.destroy! }

  test "concurrent completions save one timestamp and one transition" do
    clients = Array.new(2) do
      client = open_session
      cookie_jar = ActionDispatch::TestRequest.create.cookie_jar
      cookie_jar.signed[:session_id] = @user.sessions.create!.id
      client.cookies["session_id"] = cookie_jar[:session_id]
      client
    end
    path = update_status_job_path(@job)
    ready = Queue.new
    start = Queue.new
    threads = clients.map do |client|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          client.patch path, params: { job: { status: "completed" } }
          client.response.status
        end
      end
    end
    2.times { ready.pop }
    2.times { start << true }

    assert_equal [ 303, 303 ], threads.map(&:value)
    assert_equal "completed", @job.reload.status
    assert_not_nil @job.completed_at
    activity = @job.activities.sole
    assert_equal @user, activity.actor
    assert_equal "job_status_changed", activity.event
    assert_equal({ "previous_status" => "in_progress", "new_status" => "completed",
                   "completed_at" => @job.completed_at.iso8601(6) }, activity.metadata)
  ensure
    threads&.each(&:join)
  end
end
