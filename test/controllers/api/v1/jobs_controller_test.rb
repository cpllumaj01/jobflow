require "test_helper"

class Api::V1::JobsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @job = jobs(:kitchen_renovation)
    sign_in_as users(:one)
  end

  test "index returns only owned jobs with explicit fields and contract values" do
    change_orders(:kitchen_lighting).update!(status: "approved")
    get api_v1_jobs_url

    assert_response :success
    assert_equal "application/json", response.media_type
    assert_equal [ "jobs" ], response.parsed_body.keys
    assert_equal [ @job.id ], response.parsed_body["jobs"].map { |job| job["id"] }
    job = response.parsed_body["jobs"].first
    assert_equal %w[id name address status created_at updated_at customer original_estimate_value approved_change_order_total current_contract_value].sort, job.keys.sort
    assert_equal @job.name, job["name"]
    assert_equal @job.address, job["address"]
    assert_equal @job.status, job["status"]
    assert_equal @job.created_at.as_json, job["created_at"]
    assert_equal @job.reload.updated_at.as_json, job["updated_at"]
    assert_equal({ "id" => @job.customer.id, "name" => @job.customer.name }, job["customer"])
    assert_equal "27000.0", job["original_estimate_value"]
    assert_equal "444.0", job["approved_change_order_total"]
    assert_equal "27444.0", job["current_contract_value"]
  end

  test "show includes core fields and small related summaries" do
    get api_v1_jobs_url
    core = response.parsed_body["jobs"].first
    get api_v1_job_url(@job)

    assert_response :success
    assert_equal "application/json", response.media_type
    assert_equal [ "job" ], response.parsed_body.keys
    job = response.parsed_body["job"]
    assert_equal core, job.except("estimate", "change_orders")
    assert_equal({ "id" => @job.estimate.id, "status" => "approved", "total" => "27000.0" }, job["estimate"])
    change_order = change_orders(:kitchen_lighting)
    assert_equal [ { "id" => change_order.id, "title" => change_order.title, "status" => "draft", "total" => "444.0" } ], job["change_orders"]
    assert_equal "0.0", job["approved_change_order_total"]
  end

  test "show handles absent summaries and zero contract values" do
    job = customers(:johnson).jobs.create!(name: "New job")
    get api_v1_job_url(job)

    assert_response :success
    data = response.parsed_body["job"]
    assert_nil data["estimate"]
    assert_equal [], data["change_orders"]
    %w[original_estimate_value approved_change_order_total current_contract_value].each do |field|
      assert_equal "0.0", data[field]
    end
  end

  test "index returns an empty array when user has no jobs" do
    users(:one).customers.destroy_all
    get api_v1_jobs_url
    assert_response :success
    assert_equal({ "jobs" => [] }, response.parsed_body)
  end

  test "foreign and nonexistent jobs return identical JSON not found responses" do
    [ jobs(:office_buildout).id, Job.maximum(:id) + 1 ].each do |id|
      get api_v1_job_url(id)
      assert_response :not_found
      assert_equal "application/json", response.media_type
      assert_equal({ "error" => "Job not found" }, response.parsed_body)
    end
  end

  test "unauthenticated requests use the existing session redirect" do
    delete session_url
    [ api_v1_jobs_url, api_v1_job_url(@job) ].each do |url|
      get url
      assert_redirected_to new_session_url
    end
  end

  test "API routes do not expose writes or forms" do
    [ [ :post, "/api/v1/jobs" ], [ :patch, "/api/v1/jobs/1" ], [ :put, "/api/v1/jobs/1" ],
      [ :delete, "/api/v1/jobs/1" ], [ :get, "/api/v1/jobs/1/edit" ] ].each do |method, path|
      assert_raises(ActionController::RoutingError) do
        Rails.application.routes.recognize_path(path, method: method)
      end
    end
    get "/api/v1/jobs/new"
    assert_response :not_found
  end

  test "HTML job endpoints remain HTML" do
    [ jobs_url, job_url(@job) ].each do |url|
      get url
      assert_response :success
      assert_equal "text/html", response.media_type
      assert_select "body", text: /Kitchen Renovation/
    end
  end
end
