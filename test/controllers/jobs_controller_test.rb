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
      assert_select "li", text: "Customer must exist"
      assert_select "input[name='job[name]'][value='Bathroom Remodel']"
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
      get jobs_url, params: { q: query, status: @job.status }
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

  test "unknown status returns no matches and remains selected" do
    get jobs_url, params: { q: "Kitchen", status: "unknown" }

    assert_response :success
    assert_select "tbody tr", count: 0
    assert_select "h2", "No jobs match your filters"
    assert_select "select[name='status'] option[selected][value='unknown']"
  end

  test "filter form uses get retains values and offers reset" do
    get jobs_url, params: { q: "Kitchen", status: "in_progress" }

    assert_select "form[action=?][method='get']", jobs_path do
      assert_select "input[name='q'][value='Kitchen']"
      assert_select "select[name='status'] option[selected][value='in_progress']"
      assert_select "a[href=?]", jobs_path, text: "Reset filters"
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
      assert_select "select[name='status'][data-action='change->job-filters#submit']"
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
    26.times { customers(:johnson).jobs.create!(name: "Kitchen & bath", status: "draft") }
    customers(:fairfield).jobs.create!(name: "Kitchen & bath", status: "draft")
    customers(:johnson).jobs.create!(name: "Kitchen & bath", status: "completed")

    get jobs_url, params: { q: "Kitchen & bath", status: "draft" }

    assert_select "tbody tr", count: 25
    assert_select "turbo-frame#jobs_results a[rel='next'][data-turbo-frame='jobs_results'][data-turbo-action='advance'][href=?]",
      jobs_path(q: "Kitchen & bath", status: "draft", page: 2)

    get css_select("a[rel='next']").first["href"], headers: { "Turbo-Frame" => "jobs_results" }

    assert_response :success
    assert_select "turbo-frame#jobs_results" do
      assert_select "tbody tr", count: 1
      assert_select "nav[aria-label='Pagination'] p", text: /Showing 26–26 of 26\s+Page 2 of 2/
      assert_select "a[rel='prev'][href=?]", jobs_path(q: "Kitchen & bath", status: "draft", page: 1)
    end
  end

  test "filter submissions and reset links omit the current page" do
    get jobs_url, params: { q: "Kitchen", status: "in_progress", page: 2 }

    assert_select "form[action=?][method='get']", jobs_path do
      assert_select "input[name='page']", count: 0
      assert_select "input[name='q'][value='Kitchen']"
      assert_select "select[name='status'] option[selected][value='in_progress']"
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
