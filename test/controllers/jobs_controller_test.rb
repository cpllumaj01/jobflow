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
  end

  test "should get new" do
    get new_job_url

    assert_response :success
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
  end

  test "show displays create estimate link when job has no estimate" do
    job = customers(:johnson).jobs.create!(name: "Bathroom Remodel")

    get job_url(job)

    assert_response :success
    assert_select "h2", text: "Estimate"
    assert_select "a[href=?]", new_job_estimate_path(job), text: "Create estimate"
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

  test "index returns all owned jobs newest first without filters" do
    @job.update!(created_at: 2.days.ago)
    newer_job = customers(:johnson).jobs.create!(name: "Bathroom Remodel", created_at: 1.day.ago)

    get jobs_url

    assert_response :success
    assert_select "tbody a", count: 2
    assert_select "tbody a" do |links|
      assert_equal [job_path(newer_job), job_path(@job)], links.map { |link| link["href"] }
    end
    assert_select "a[href=?]", job_path(jobs(:office_buildout)), count: 0
  end

  test "search matches job name address and customer name case insensitively" do
    unrelated_customer = @user.customers.create!(name: "Smith Residence")
    unrelated_job = unrelated_customer.jobs.create!(name: "Deck Replacement", address: "900 Oak Road")

    ["  kItChEn  ", "mAiN sTrEeT", "jOhNsOn"].each do |query|
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

    ["Kitchen", "Main Street", "Johnson"].each do |query|
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

    ["%", "_"].each do |query|
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
