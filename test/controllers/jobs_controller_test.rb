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

  test "show displays estimate status and view link when job has an estimate" do
    get job_url(@job)

    assert_response :success
    assert_select "h2", text: "Estimate"
    assert_select "span", text: @job.estimate.status.humanize
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
end
