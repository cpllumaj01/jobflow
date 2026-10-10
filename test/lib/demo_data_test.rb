require "test_helper"
require "rake"
require "tmpdir"
require "fileutils"
require Rails.root.join("lib/demo_data")

class DemoDataTest < ActiveSupport::TestCase
  setup do
    @storage_service = ActiveStorage::Blob.service
    @original_storage_root = @storage_service.root
    @storage_directory = Dir.mktmpdir("jobflow-demo-data-")
    @storage_service.root = @storage_directory

    Rails.application.load_tasks unless Rake::Task.task_defined?("demo:bootstrap")
    @task = Rake::Task["demo:bootstrap"]
    @original_env = ENV.to_h.slice("ALLOW_PRODUCTION_DEMO_BOOTSTRAP", "DEMO_PASSWORD")
    ENV.delete("ALLOW_PRODUCTION_DEMO_BOOTSTRAP")
    ENV.delete("DEMO_PASSWORD")
  end

  teardown do
    %w[ALLOW_PRODUCTION_DEMO_BOOTSTRAP DEMO_PASSWORD].each do |key|
      ENV[key] = @original_env[key]
    end
    @storage_service.root = @original_storage_root
    FileUtils.remove_entry(@storage_directory)
  end

  test "production task creates repeatable demo data and preserves unrelated users" do
    unrelated = users(:one)
    customer = unrelated.customers.first
    job = customer.jobs.create!(name: "Keep this project", status: "draft")
    job.files.attach(io: StringIO.new("Keep this file"), filename: "keep.txt", content_type: "text/plain")
    original_records = [ unrelated, customer, job ].map { |record| record.reload.attributes }
    original_user_ids = User.ids.sort
    ENV["ALLOW_PRODUCTION_DEMO_BOOTSTRAP"] = "true"
    ENV["DEMO_PASSWORD"] = "local-test-demo-password"

    2.times do
      in_production do
        output, = capture_io { invoke_bootstrap }
        refute_includes output, ENV["DEMO_PASSWORD"]
      end

      demo = User.find_by!(email_address: DemoData::EMAIL)
      assert demo.authenticate(ENV["DEMO_PASSWORD"])
      assert_equal original_user_ids, User.where.not(id: demo.id).ids.sort
      assert_equal original_records, [ unrelated, customer, job ].map { |record| record.reload.attributes }
      assert_equal "Keep this file", job.files.first.download
      assert_equal 4, demo.customers.count
      assert_equal 6, demo.jobs.count
      assert_equal 6, Estimate.where(job_id: demo.jobs.select(:id)).count
      assert_equal 4, ChangeOrder.where(job_id: demo.jobs.select(:id)).count
      assert_equal Job::STATUSES.sort, demo.jobs.pluck(:status).sort
      kitchen = demo.jobs.find_by!(name: "Kitchen Renovation")
      assert_equal 25_960, kitchen.current_contract_value
      assert_equal %w[approved draft pending rejected], kitchen.change_orders.pluck(:status).sort
      assert_equal 1, ActiveStorage::Attachment.where(record: demo.jobs).count
      assert_equal "kitchen-renovation-scope.txt", kitchen.files.first.filename.to_s
      assert_includes kitchen.files.first.download, "Fictional project document"
    end
  end

  test "bootstrap rejects non-production even with opt-in" do
    ENV["ALLOW_PRODUCTION_DEMO_BOOTSTRAP"] = "true"
    ENV["DEMO_PASSWORD"] = "local-test-demo-password"
    assert_bootstrap_rejected(/production-only/)
  end

  test "production bootstrap requires exact opt-in and a suitable password before changing data" do
    in_production do
      [ nil, "false", "1", "TRUE" ].each do |opt_in|
        ENV["ALLOW_PRODUCTION_DEMO_BOOTSTRAP"] = opt_in
        assert_bootstrap_rejected(/ALLOW_PRODUCTION_DEMO_BOOTSTRAP/)
      end
      ENV["ALLOW_PRODUCTION_DEMO_BOOTSTRAP"] = "true"
      [ nil, "", " " * 16, "password", "x" * 73 ].each do |password|
        ENV["DEMO_PASSWORD"] = password
        assert_bootstrap_rejected(/DEMO_PASSWORD/)
      end
    end
  end

  test "normal production seeds remain blocked even with bootstrap opt-in" do
    ENV["ALLOW_PRODUCTION_DEMO_BOOTSTRAP"] = "true"
    ENV["DEMO_PASSWORD"] = "local-test-demo-password"
    in_production do
      assert_no_difference [ "User.count", "Customer.count", "Job.count" ] do
        _out, err = capture_io do
          assert_raises(SystemExit) { load Rails.root.join("db/seeds.rb") }
        end
        assert_match(/disabled in production/, err)
      end
    end
  end

  test "a failed refresh rolls back the demo password and project replacement" do
    demo = DemoData.populate!(password: "original-demo-password")
    customer_ids = demo.customers.ids
    digest = demo.password_digest
    # Fail after earlier customers have been recreated, before commit.
    failure = ->(customer) { raise IOError, "demo failure" if customer.name == "Harbor Dental Group" }
    begin
      Customer.set_callback(:create, :before, failure)
      assert_raises(IOError) { DemoData.populate!(password: "replacement-demo-password") }
    ensure
      Customer.skip_callback(:create, :before, failure)
    end
    assert_equal customer_ids.sort, demo.reload.customers.ids.sort
    assert_equal digest, demo.password_digest
  end

  private
    def invoke_bootstrap
      @task.invoke
    ensure
      @task.reenable
    end

    def in_production
      original_env = Rails.env
      Rails.env = "production"
      yield
    ensure
      Rails.env = original_env
    end

    def assert_bootstrap_rejected(message)
      assert_no_difference [ "User.count", "Customer.count", "Job.count" ] do
        _out, err = capture_io do
          assert_raises(SystemExit) { invoke_bootstrap }
        end
        assert_match message, err
      end
    end
end
