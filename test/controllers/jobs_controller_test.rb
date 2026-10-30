require "test_helper"

class JobsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @job = jobs(:kitchen_renovation)

    sign_in_as @user
  end

  test "should get index" do
    get jobs_url

    assert_response :success
    assert_select "body", text: /Kitchen Renovation/
    assert_select "body", text: /Office Buildout/, count: 0
    assert_select "ul[aria-label='Jobs'] li", count: 1 do
      assert_select "h2", @job.name
      assert_select "p", @job.address
      assert_select "dd", @job.customer.name
      assert_select "span", @job.status.humanize
      assert_select "a[href=?][aria-label=?]", job_path(@job), "View #{@job.name}"
    end
  end

  test "should get new" do
    get new_job_url

    assert_response :success
  end

  test "new only offers owned customers without a blank option" do
    get new_job_url

    assert_response :success
    assert_select "select[name='job[customer_id]'] option", count: @user.customers.count
    assert_select "select[name='job[customer_id]'] option[value='']", count: 0
    assert_select "select[name='job[customer_id]'] option[value=?]", customers(:fairfield).id, count: 0
  end

  test "creation requires a customer" do
    [ nil, "" ].each do |customer_id|
      assert_no_difference("Job.count") do
        post jobs_url, params: { job: { customer_id: customer_id, name: "Bathroom Remodel" } }
      end

      assert_response :unprocessable_entity
      assert_select "#job_customer_id_error", text: "Customer must exist"
      assert_select '#job_customer_id[aria-invalid="true"][aria-describedby="job_customer_id_error"]'
      assert_select "input[name='job[name]'][value='Bathroom Remodel']"
    end
  end

  test "invalid job name renders inline on create and update with valid help associations preserved" do
    [ :post, :patch ].each do |method|
      public_send(method, method == :post ? jobs_url : job_url(@job), params: {
        job: { customer_id: @job.customer_id, name: "", description: "Keep this description", estimated_completion_date: "2027-01-01" }
      })

      assert_response :unprocessable_entity
      assert_select '#job_name[aria-invalid="true"][aria-describedby="job_name_error"]'
      assert_select "#job_name_error", text: "Name can't be blank"
      assert_select "textarea#job_description", text: "Keep this description"
      assert_select '#job_estimated_completion_date[value="2027-01-01"][aria-describedby="estimated-completion-help"]:not([aria-invalid])'
      assert_select "#estimated-completion-help", count: 1
      assert_select '[role="alert"] li', count: 0
    end
  end

  test "creation rejects a nonexistent customer" do
    assert_no_difference("Job.count") do
      post jobs_url, params: { job: { customer_id: Customer.maximum(:id) + 1, name: "Bathroom Remodel" } }
    end

    assert_response :not_found
  end

  test "new and failed creation show an empty state when user has no customers" do
    @user.customers.destroy_all

    get new_job_url

    assert_response :success
    assert_select "h2", "No customers yet"
    assert_select "a[href=?]", new_customer_path, text: "New customer"
    assert_select "form[action=?]", jobs_path, count: 0

    assert_no_difference("Job.count") do
      post jobs_url, params: { job: { name: "Bathroom Remodel" } }
    end

    assert_response :unprocessable_entity
    assert_select "h2", "No customers yet"
    assert_select "a[href=?]", new_customer_path, text: "New customer"
    assert_select "form[action=?]", jobs_path, count: 0
  end

  test "should create job" do
    assert_difference("Job.count") do
      post jobs_url, params: {
        job: {
          customer_id: customers(:johnson).id,
          name: "Bathroom Remodel",
          description: "Full bathroom renovation",
          address: "123 Main Street",
          status: "draft",
          start_date: "2026-10-01",
          estimated_completion_date: "2026-11-01"
        }
      }
    end

    job = Job.find_by!(name: "Bathroom Remodel")

    assert_equal customers(:johnson), job.customer
    assert_equal @user, job.customer.user
    assert_redirected_to job_url(job)
  end

  test "cannot create job for another user's customer" do
    assert_no_difference("Job.count") do
      post jobs_url, params: {
        job: {
          customer_id: customers(:fairfield).id,
          name: "Unauthorized Job",
          status: "draft"
        }
      }
    end

    assert_response :not_found
  end

  test "should show job" do
    get job_url(@job)

    assert_response :success
  end

  test "show displays estimate status total and view link when job has an estimate" do
    get job_url(@job)

    assert_response :success
    assert_select "h2", text: "Estimate"
    assert_select "span", text: @job.estimate.status.humanize
    assert_select "p", text: "Estimate total" do |labels|
      assert_equal "$27,000.00", labels.first.next_element.text.strip
    end
    assert_select "a[href=?]", job_estimate_path(@job), text: /View estimate/
    assert_select "a[href=?]", new_job_estimate_path(@job), count: 0
    assert_select "p", text: /No estimate yet/, count: 0
  end

  test "show displays create estimate link when job has no estimate" do
    job = customers(:johnson).jobs.create!(name: "Bathroom Remodel")

    get job_url(job)

    assert_response :success
    assert_select "h2", text: "Estimate"
    assert_select "p", text: "No estimate yet. Create one to outline the work and pricing for this job."
    assert_select "a[href=?]", new_job_estimate_path(job), text: "Create estimate", count: 1
    assert_select "a[href=?]", job_estimate_path(job), count: 0
  end

  test "should get edit" do
    get edit_job_url(@job)

    assert_response :success
  end

  test "should update job" do
    patch job_url(@job), params: {
      job: {
        customer_id: customers(:johnson).id,
        name: "Kitchen Remodel",
        status: "in_progress"
      }
    }

    assert_redirected_to job_url(@job)
    assert_equal "Kitchen Remodel", @job.reload.name
  end

  test "quick status updates support every existing transition without duplicate history" do
    freeze_time do
      Job::STATUSES.each do |previous_status|
        Job::STATUSES.each do |status|
          @job.update!(status: previous_status)
          previous_completion = @job.completed_at
          assert_difference("Activity.count", status == previous_status ? 0 : 1) do
            patch update_status_job_url(@job), params: { job: { status: status } }
          end

          assert_response :see_other
          assert_redirected_to job_url(@job)
          assert_equal status, @job.reload.status
          if status == "completed"
            assert_equal previous_completion || Time.current, @job.completed_at
          else
            assert_nil @job.completed_at
          end
          next if status == previous_status

          activity = @job.activities.newest_first.first
          assert_equal @user, activity.actor
          assert_equal "job_status_changed", activity.event
          expected = { "previous_status" => previous_status, "new_status" => status }
          expected["completed_at"] = @job.completed_at.iso8601(6) if status == "completed"
          expected["previous_completed_at"] = previous_completion.iso8601(6) if previous_status == "completed"
          assert_equal expected, activity.metadata
        end
      end
    end
  end

  test "completion reopening and recompletion preserve earlier history and use server time" do
    Time.use_zone("America/New_York") do
      freeze_time do
        patch update_status_job_url(@job), params: { job: { status: "completed" } }
        assert_equal Time.current, @job.reload.completed_at
      end
      first_completion = @job.completed_at
      completion_event = @job.activities.sole
      recorded_event = completion_event.attributes

      travel 1.hour do
        assert_no_difference("Activity.count") do
          patch update_status_job_url(@job), params: { job: { status: "completed" } }
        end
        assert_equal first_completion, @job.reload.completed_at
        patch update_status_job_url(@job), params: { job: { status: "in_progress" } }
        assert_nil @job.reload.completed_at
        assert_equal first_completion.iso8601(6), @job.activities.newest_first.first.metadata["previous_completed_at"]
      end

      travel 1.day do
        patch update_status_job_url(@job), params: { job: { status: "completed" } }
        assert_equal Time.current, @job.reload.completed_at
        assert_operator @job.completed_at, :>, first_completion
      end
      assert_equal 3, @job.activities.count
      assert_equal recorded_event, completion_event.reload.attributes
      get job_url(@job)
      assert_select "section[aria-labelledby='activity-heading']" do
        assert_select "li", count: 3
        assert_select "dt", text: "Completed at", count: 2
        assert_select "dt", text: "Previous completed at", count: 1
        assert_select "dd", text: first_completion.in_time_zone.strftime("%b %-d, %Y at %-I:%M %p %Z"), count: 2
      end
    end
  end

  test "invalid quick status updates show validation errors and the persisted status" do
    %w[in_progress completed].each do |persisted_status|
      @job.update!(status: persisted_status)
      completion = @job.completed_at
      [ "unknown", "", nil ].each do |status|
        assert_no_difference("Activity.count") do
          patch update_status_job_url(@job), params: { job: { status: status } }
        end
        assert_response :unprocessable_entity
        assert_equal persisted_status, @job.reload.status
        completion ? assert_equal(completion, @job.completed_at) : assert_nil(@job.completed_at)
        assert_select "main", text: /Status is not included in the list/
        assert_select "#job-status", text: persisted_status.humanize
        assert_select "button[aria-current='true'][disabled]", text: /#{Regexp.escape(persisted_status.humanize)}\s+Current/
        assert_select "dt", text: "Completed", count: persisted_status == "completed" ? 1 : 0
      end
    end
  end

  test "header status forms preserve CSRF protection" do
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    get job_url(@job)
    assert_select "#job-header form[action=?]", update_status_job_path(@job), count: Job::STATUSES.size - 1 do
      assert_select "input[name='authenticity_token']", count: Job::STATUSES.size - 1
    end
    token = css_select("#job-header input[name='authenticity_token']").first["value"]
    assert_no_difference("Activity.count") do
      patch update_status_job_url(@job), params: { job: { status: "quoted" } }
    end
    assert_response :unprocessable_entity
    assert_equal "in_progress", @job.reload.status
    patch update_status_job_url(@job), params: { authenticity_token: token, job: { status: "quoted" } }
    assert_response :see_other
    assert_equal "quoted", @job.reload.status
  ensure
    ActionController::Base.allow_forgery_protection = previous
  end

  test "quick status updates require a scalar status and authentication and ownership" do
    [ {}, { job: { status: [ "completed" ] } }, { job: { status: { value: "completed" } } } ].each do |attributes|
      assert_no_difference("Activity.count") { patch update_status_job_url(@job), params: attributes }
      assert_response :bad_request
    end
    foreign_job = jobs(:office_buildout)
    original = foreign_job.attributes
    assert_no_difference("Activity.count") do
      patch update_status_job_url(foreign_job), params: { job: { status: "completed" } }
    end
    assert_response :not_found
    assert_equal original, foreign_job.reload.attributes

    sign_out
    assert_no_difference("Activity.count") do
      patch update_status_job_url(@job), params: { job: { status: "completed" } }
    end
    assert_redirected_to new_session_url
    assert_equal "in_progress", @job.reload.status
  end

  test "quick status updates ignore completion ownership and unrelated attributes" do
    freeze_time do
      patch update_status_job_url(@job), params: {
        id: jobs(:office_buildout).id,
        job: { status: "completed", completed_at: "2000-01-01", customer_id: customers(:fairfield).id,
               name: "Forged name", actor_id: users(:two).id, metadata: { new_status: "forged" } }
      }
      assert_response :see_other
      assert_equal "completed", @job.reload.status
      assert_equal Time.current, @job.completed_at
      assert_equal "Kitchen Renovation", @job.name
      assert_equal customers(:johnson), @job.customer
      assert_equal @user, @job.activities.sole.actor
      assert_equal "quoted", jobs(:office_buildout).reload.status
    end
  end

  test "creation and normal editing ignore manual actual completion timestamps" do
    post jobs_url, params: { job: { name: "Planned work", customer_id: @job.customer_id,
      estimated_completion_date: "2026-12-01", completed_at: "2000-01-01" } }
    created = @user.jobs.find_by!(name: "Planned work")
    assert_nil created.completed_at
    assert_equal Date.new(2026, 12, 1), created.estimated_completion_date

    freeze_time do
      patch job_url(created), params: { job: { customer_id: created.customer_id,
        status: "completed", completed_at: "2000-01-01" } }
      assert_redirected_to job_url(created)
      assert_equal Time.current, created.reload.completed_at
      assert_equal Time.current.iso8601(6), created.activities.sole.metadata["completed_at"]
      post jobs_url, params: { job: { name: "Finished work", customer_id: @job.customer_id,
        status: "completed", completed_at: "2000-01-01" } }
      assert_equal Time.current, @user.jobs.find_by!(name: "Finished work").completed_at
    end
    completed_at = created.completed_at
    patch job_url(created), params: { job: { customer_id: created.customer_id, name: "Renamed", completed_at: nil } }
    assert_redirected_to job_url(created)
    assert_equal completed_at, created.reload.completed_at
  end

  test "new and edit forms keep estimated completion optional and omit actual completion" do
    [ new_job_url, edit_job_url(@job) ].each do |url|
      get url
      assert_response :success
      assert_select "[name='job[completed_at]']", count: 0
      assert_select "label[for='job_estimated_completion_date']", text: "Estimated completion (optional)"
      assert_select "input[type='date'][name='job[estimated_completion_date]']", count: 1
      assert_select "input[name='job[estimated_completion_date]'][required]", count: 0
    end
  end

  test "show offers status actions and only displays actual completion for completed jobs" do
    Job::STATUSES.each do |status|
      @job.update!(status: status)
      get job_url(@job)
      assert_response :success
      assert_select "section[aria-labelledby='job-status-heading']", count: 0
      assert_select "#job-header" do
        assert_select "#job-status", text: status.humanize
        assert_select "summary", text: "Change status"
        assert_select "button[aria-current='true'][disabled]", text: /#{Regexp.escape(status.humanize)}\s+Current/, count: 1
        assert_select "form[action=?] input[name='job[status]']", update_status_job_path(@job) do |inputs|
          assert_equal Job::STATUSES - [ status ], inputs.map { |input| input["value"] }.sort_by { |value| Job::STATUSES.index(value) }
        end
        assert_select "input[name='_method'][value='patch']", count: Job::STATUSES.size - 1
        assert_select "button[type='submit']", text: "Complete job", count: %w[completed cancelled].include?(status) ? 0 : 1
        assert_select "a[href=?]", edit_job_path(@job), text: "Edit job"
        assert_select "select", count: 0
        assert_select "input[type='submit'][value='Update status']", count: 0
        assert_select "details[name='job-status-confirmation']", count: status == "completed" ? 5 : (status == "cancelled" ? 0 : 1)
      end
      assert_select "dt", text: "Completed", count: status == "completed" ? 1 : 0
    end

    @job.update_columns(status: "draft", completed_at: 1.day.ago)
    assert_no_difference("Activity.count") { get job_url(@job) }
    assert_select "dt", text: "Completed", count: 0
  end

  test "cannot reassign job to another user's customer" do
    patch job_url(@job), params: {
      job: {
        customer_id: customers(:fairfield).id,
        name: @job.name,
        status: @job.status
      }
    }

    assert_response :not_found
    assert_equal customers(:johnson), @job.reload.customer
  end

  test "cannot access another user's job" do
    get job_url(jobs(:office_buildout))

    assert_response :not_found
  end

  test "should destroy job" do
    assert_difference("Job.count", -1) do
      delete job_url(@job)
    end

    assert_redirected_to jobs_url
  end

  test "cannot destroy another user's job" do
    assert_no_difference("Job.count") do
      delete job_url(jobs(:office_buildout))
    end

    assert_response :not_found
  end

  test "new can preselect customer" do
    get new_job_url(customer_id: customers(:johnson).id)

    assert_response :success
    assert_select "select[name='job[customer_id]'] option[selected]", text: "Johnson Residence"
  end

  test "cannot preselect another user's customer" do
    get new_job_url(customer_id: customers(:fairfield).id)

    assert_response :not_found
  end

  test "index returns owned jobs newest first without filters" do
    @job.update!(created_at: 2.days.ago)
    newer_job = customers(:johnson).jobs.create!(name: "Bathroom Remodel", created_at: 1.day.ago)

    get jobs_url

    assert_response :success
    assert_select "tbody a", count: 2
    assert_select "tbody a" do |links|
      assert_equal [ job_path(newer_job), job_path(@job) ], links.map { |link| link["href"] }
    end
    assert_select "a[href=?]", job_path(jobs(:office_buildout)), count: 0
  end

  test "search matches job name address and customer name case insensitively" do
    unrelated_customer = @user.customers.create!(name: "Smith Residence")
    unrelated_job = unrelated_customer.jobs.create!(name: "Deck Replacement", address: "900 Oak Road")

    [ "  kItChEn  ", "mAiN sTrEeT", "jOhNsOn" ].each do |query|
      get jobs_url, params: { q: query }

      assert_response :success
      assert_select "tbody a", count: 1
      assert_select "tbody a[href=?]", job_path(@job)
      assert_select "tbody a[href=?]", job_path(unrelated_job), count: 0
    end
  end

  test "search and status never expose another user's matching jobs" do
    other_job = jobs(:office_buildout)
    other_job.update!(name: @job.name, address: @job.address, status: @job.status)
    customers(:fairfield).update!(name: customers(:johnson).name)

    [ "Kitchen", "Main Street", "Johnson" ].each do |query|
      get jobs_url, params: { q: query, status: [ @job.status, "quoted" ] }
      assert_select "tbody a", count: 1
      assert_select "tbody a[href=?]", job_path(@job)
      assert_select "tbody a[href=?]", job_path(other_job), count: 0
    end
  end

  test "status filters use existing job statuses" do
    Job::STATUSES.each do |status|
      @job.update!(status: status)
      get jobs_url, params: { status: status }
      assert_select "tbody a", count: 1
      assert_select "tbody a[href=?]", job_path(@job)
    end
  end

  test "search and status filters work together" do
    customers(:johnson).jobs.create!(name: "Kitchen Addition", status: "draft")
    customers(:johnson).jobs.create!(name: "Deck Replacement", status: "in_progress")

    get jobs_url, params: { q: "Kitchen", status: "in_progress" }

    assert_select "tbody a", count: 1
    assert_select "tbody a[href=?]", job_path(@job)
  end

  test "multiple statuses match their union and combine with search" do
    draft = customers(:johnson).jobs.create!(name: "Kitchen Addition", status: "draft")
    customers(:johnson).jobs.create!(name: "Deck Replacement", status: "draft")
    customers(:johnson).jobs.create!(name: "Kitchen Remodel", status: "completed")

    get jobs_url, params: { q: "kItChEn", status: [ "draft", "in_progress" ] }

    assert_response :success
    assert_select "tbody a", count: 2
    [ draft, @job ].each { |job| assert_select "tbody a[href=?]", job_path(job) }
    assert_select "input[name='status[]'][checked]", count: 2
    assert_select "summary", text: /2 statuses selected/
  end

  test "blank and duplicate statuses normalize without changing the selected union" do
    [ nil, "", "  ", [], [ "", " " ] ].each do |statuses|
      get jobs_url, params: { status: statuses }

      assert_response :success
      assert_select "tbody a[href=?]", job_path(@job)
      assert_select "input[name='status[]'][checked]", count: 0
      assert_select "[data-job-filters-target='selection']", text: "All statuses"
    end

    get jobs_url, params: { status: [ " in_progress ", "", "in_progress", " " ] }

    assert_select "tbody a", count: 1
    assert_select "input[name='status[]'][checked]", count: 1
    assert_select "input[name='status[]'][checked][value='in_progress']"
  end

  test "unknown statuses never broaden even partially valid filters and remain removable" do
    [ [ "unknown" ], [ "", "unknown" ], [ "in_progress", "unknown" ], [ "' OR 1=1 --" ], [ "<script>alert(1)</script>" ] ].each do |statuses|
      get jobs_url, params: { status: statuses }

      assert_response :success
      assert_select "tbody tr", count: 0
      assert_select "h2", "No jobs match your filters"
      assert_select "input[name='status[]'][checked]", count: statuses.reject(&:blank?).uniq.size
      assert_select "p", "Unknown statuses return no jobs. Clear them or choose Reset filters to continue."
      assert_select "fieldset script", count: 0
    end
  end

  test "malformed status structures return bad request instead of all jobs" do
    [ { value: "in_progress" }, [ { value: "in_progress" } ], [ [ "in_progress" ] ], [ "in_progress", { value: "draft" } ] ].each do |statuses|
      get "#{jobs_url}?#{Rack::Utils.build_nested_query(status: statuses)}"

      assert_response :bad_request
      assert_select "turbo-frame#jobs_results", count: 0
    end
  end

  test "unknown status returns no matches and remains selected" do
    get jobs_url, params: { q: "Kitchen", status: "unknown" }

    assert_response :success
    assert_select "tbody tr", count: 0
    assert_select "h2", "No jobs match your filters"
    assert_select "input[name='status[]'][checked][value='unknown']"
  end

  test "filter form uses get retains values and offers reset" do
    get jobs_url, params: { q: "Kitchen", status: "in_progress" }

    assert_select "form[action=?][method='get']", jobs_path do
      assert_select "input[name='q'][value='Kitchen']"
      assert_select "input[name='status[]'][checked][value='in_progress']"
      assert_select "a[href=?]", jobs_path, text: "Reset filters"
      assert_select "input[type='submit'][value='Filter jobs'][data-job-filters-target='manualSubmit']:not([hidden])"
      assert_select "fieldset legend", text: "Statuses"
      assert_select "input[type='checkbox'][name='status[]']", count: Job::STATUSES.size
    end
  end

  test "unmatched search displays filtered empty state" do
    get jobs_url, params: { q: "missing job" }

    assert_response :success
    assert_select "h2", "No jobs match your filters"
    assert_select "h2", text: "No jobs yet", count: 0
  end

  test "blank filters behave like no filters" do
    get jobs_url, params: { q: "   ", status: "" }

    assert_select "tbody a[href=?]", job_path(@job)
  end

  test "search treats SQL wildcards as literal characters" do
    special_job = customers(:johnson).jobs.create!(name: "100%_complete")

    [ "%", "_" ].each do |query|
      get jobs_url, params: { q: query }
      assert_select "tbody a", count: 1
      assert_select "tbody a[href=?]", job_path(special_job)
    end

    get jobs_url, params: { q: "' OR 1=1 --" }
    assert_response :success
    assert_select "tbody tr", count: 0
  end

  test "filter form targets results frame while keeping inputs outside it" do
    get jobs_url

    assert_select "form[data-controller='job-filters'][data-turbo-frame='jobs_results'][data-turbo-action='replace']" do
      assert_select "input[name='q'][data-action='input->job-filters#search']"
      assert_select "input[name='status[]'][data-action='change->job-filters#changeStatuses']"
      assert_select "a[href=?][data-action='click->job-filters#cancel']", jobs_path
    end
    assert_select "turbo-frame#jobs_results[target='_top'][data-turbo-action='replace']" do
      assert_select "form", count: 0
      assert_select "a[href=?]", job_path(@job)
    end
  end

  test "turbo frame requests return filtered results" do
    customers(:johnson).jobs.create!(name: "Deck Replacement", status: "draft")

    get jobs_url, params: { q: "Kitchen", status: "in_progress" }, headers: { "Turbo-Frame" => "jobs_results" }

    assert_response :success
    assert_select "turbo-frame#jobs_results" do
      assert_select "tbody a", count: 1
      assert_select "a[href=?]", job_path(@job)
    end
  end

  test "pagination has stable boundaries for jobs with identical creation times" do
    @job.update!(created_at: 1.day.ago)
    timestamp = Time.current
    added_jobs = Array.new(50) do |index|
      customers(:johnson).jobs.create!(name: "Paged job #{index}", created_at: timestamp)
    end
    expected_jobs = added_jobs.reverse + [ @job ]

    get jobs_url
    assert_select "tbody a" do |links|
      assert_equal expected_jobs.first(25).map { |job| job_path(job) }, links.map { |link| link["href"] }
    end
    assert_select "nav[aria-label='Pagination']" do
      assert_select "p", text: /Showing 1–25 of 51\s+Page 1 of 3/
      assert_select "span[aria-disabled='true']", text: "Previous"
      assert_select "a[rel='prev']", count: 0
    end

    get css_select("a[rel='next']").first["href"]
    assert_select "tbody a" do |links|
      assert_equal expected_jobs.slice(25, 25).map { |job| job_path(job) }, links.map { |link| link["href"] }
    end
    assert_select "nav[aria-label='Pagination'] p", text: /Showing 26–50 of 51\s+Page 2 of 3/

    get css_select("a[rel='next']").first["href"]
    assert_select "tbody a[href=?]", job_path(@job), count: 1
    assert_select "tbody a", count: 1
    assert_select "nav[aria-label='Pagination']" do
      assert_select "p", text: /Showing 51–51 of 51\s+Page 3 of 3/
      assert_select "span[aria-disabled='true']", text: "Next"
      assert_select "a[rel='next']", count: 0
    end

    get css_select("a[rel='prev']").first["href"]
    assert_select "nav[aria-label='Pagination'] p", text: /Page 2 of 3/
    assert_select "tbody a[href=?]", job_path(jobs(:office_buildout)), count: 0
  end

  test "pagination preserves combined filters and targets the results frame" do
    26.times do |index|
      customers(:johnson).jobs.create!(name: "Kitchen & bath", status: index.even? ? "draft" : "quoted")
    end
    customers(:fairfield).jobs.create!(name: "Kitchen & bath", status: "draft")
    customers(:johnson).jobs.create!(name: "Kitchen & bath", status: "completed")

    get jobs_url, params: { q: "Kitchen & bath", status: [ "draft", "quoted" ] }

    assert_select "tbody tr", count: 25
    assert_select "turbo-frame#jobs_results a[rel='next'][data-turbo-frame='jobs_results'][data-turbo-action='advance'][href=?]",
      jobs_path(q: "Kitchen & bath", status: [ "draft", "quoted" ], page: 2)

    get css_select("a[rel='next']").first["href"], headers: { "Turbo-Frame" => "jobs_results" }

    assert_response :success
    assert_select "turbo-frame#jobs_results" do
      assert_select "tbody tr", count: 1
      assert_select "nav[aria-label='Pagination'] p", text: /Showing 26–26 of 26\s+Page 2 of 2/
      assert_select "a[rel='prev'][href=?]", jobs_path(q: "Kitchen & bath", status: [ "draft", "quoted" ], page: 1)
    end
  end

  test "filter submissions and reset links omit the current page" do
    get jobs_url, params: { q: "Kitchen", status: "in_progress", page: 2 }

    assert_select "form[action=?][method='get']", jobs_path do
      assert_select "input[name='page']", count: 0
      assert_select "input[name='q'][value='Kitchen']"
      assert_select "input[name='status[]'][checked][value='in_progress']"
      assert_select "a[href=?]", jobs_path, text: "Reset filters"
    end
  end

  test "invalid page values use the first page and excessive values use the last page" do
    25.times { |index| customers(:johnson).jobs.create!(name: "Paged job #{index}", created_at: 1.day.from_now) }

    [ "invalid", "", "0", "-2", "1.5", "2oops", [ "2" ], { number: "2" } ].each do |page|
      get jobs_url, params: { page: page }

      assert_response :success
      assert_select "tbody tr", count: 25
      assert_select "nav[aria-label='Pagination'] p", text: /Page 1 of 2/
    end

    get jobs_url, params: { page: "9" * 100 }
    assert_response :success
    assert_select "tbody a[href=?]", job_path(@job)
    assert_select "tbody tr", count: 1
    assert_select "nav[aria-label='Pagination'] p", text: /Page 2 of 2/
  end

  test "single and empty pages have no pagination links" do
    get jobs_url
    assert_select "nav[aria-label='Pagination'] p", text: /Showing 1–1 of 1\s+Page 1 of 1/
    assert_select "nav[aria-label='Pagination'] a", count: 0

    get jobs_url, params: { q: "No matches", page: 999 }
    assert_response :success
    assert_select "h2", "No jobs match your filters"
    assert_select "nav[aria-label='Pagination']", count: 0

    @job.destroy!
    get jobs_url, params: { page: 999 }
    assert_select "h2", "No jobs yet"
    assert_select "nav[aria-label='Pagination']", count: 0
  end

  test "pagination only instantiates one page of jobs and preloads customers" do
    30.times { |index| @user.customers.create!(name: "Customer #{index}").jobs.create!(name: "Job #{index}") }
    instantiated = Hash.new(0)
    subscriber = ->(event) { instantiated[event.payload[:class_name]] += event.payload[:record_count] }
    customer_queries = 0
    query_subscriber = ->(event) { customer_queries += 1 if event.payload[:name] == "Customer Load" }

    ActiveSupport::Notifications.subscribed(query_subscriber, "sql.active_record") do
      ActiveSupport::Notifications.subscribed(subscriber, "instantiation.active_record") do
        get jobs_url
      end
    end

    assert_response :success
    assert_equal 25, instantiated["Job"]
    assert_equal 25, instantiated["Customer"]
    assert_equal 1, customer_queries
    assert_select "tbody tr", count: 25
  end

  test "job summary displays unapproved estimate total separately from contract value" do
    @job.estimate.update!(status: "draft")

    get job_url(@job)

    assert_response :success
    assert_select "span", text: "Draft"
    assert_select "p", text: "Estimate total" do |labels|
      assert_equal "$27,000.00", labels.first.next_element.text.strip
    end
    assert_select "a[href=?]", job_estimate_path(@job), text: /View estimate/
  end
end
