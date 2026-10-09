require "test_helper"

class JobAttachmentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @job = jobs(:kitchen_renovation)
    sign_in_as users(:one)
  end

  test "uploads multiple files and appends subsequent uploads" do
    assert_difference("ActiveStorage::Attachment.count", 2) do
      post job_attachments_url(@job), params: { job: { files: [ upload, upload ] } }
    end
    assert_redirected_to job_url(@job)
    post job_attachments_url(@job), params: { job: { files: [ upload ] } }
    assert_equal 3, @job.files.count

    get job_url(@job)
    assert_response :success
    @job.files.each do |file|
      assert_select "a[href=?]", job_attachment_path(@job, file), text: "project.txt"
    end
  end

  test "empty job displays upload form and empty state" do
    get job_url(@job)
    assert_select "p", text: "No attachments yet."
    assert_select "form[action=?][enctype='multipart/form-data']", job_attachments_path(@job) do
      assert_select "input[type='file'][multiple][name='job[files][]']"
    end
  end

  test "owner can download file" do
    @job.files.attach(upload)
    get job_attachment_url(@job, @job.files.first)
    assert_response :success
    assert_equal File.read(file_fixture("project.txt")), response.body
    assert_match(/attachment;/, response.headers["Content-Disposition"])
  end

  test "removing one file preserves job and other files and purges storage" do
    @job.files.attach([ upload, upload ])
    file = @job.files.first
    blob = file.blob
    assert_no_difference("Job.count") do
      assert_difference("ActiveStorage::Attachment.count", -1) do
        delete job_attachment_url(@job, file)
      end
    end
    assert_redirected_to job_url(@job)
    assert_equal 1, @job.reload.files.count
    assert_not ActiveStorage::Blob.exists?(blob.id)
    assert_not blob.service.exist?(blob.key)
  end

  test "cannot upload to another users job" do
    assert_no_difference("ActiveStorage::Attachment.count") do
      post job_attachments_url(jobs(:office_buildout)), params: { job: { files: [ upload ] } }
    end
    assert_response :not_found
  end

  test "cannot download or remove another users attachment or substitute its id" do
    other_job = jobs(:office_buildout)
    other_job.files.attach(upload)
    file = other_job.files.first
    [ other_job, @job ].each do |job|
      get job_attachment_url(job, file)
      assert_response :not_found
      assert_no_difference("ActiveStorage::Attachment.count") do
        delete job_attachment_url(job, file)
      end
      assert_response :not_found
    end
  end

  test "cannot substitute attachment from another owned job" do
    other_job = customers(:johnson).jobs.create!(name: "Other job")
    other_job.files.attach(upload)
    file = other_job.files.first
    get job_attachment_url(@job, file)
    assert_response :not_found
    assert_no_difference("ActiveStorage::Attachment.count") do
      delete job_attachment_url(@job, file)
    end
    assert_response :not_found
  end

  test "attachment actions require authentication" do
    @job.files.attach(upload)
    file = @job.files.first
    delete session_url
    get job_attachment_url(@job, file)
    assert_redirected_to new_session_url
    assert_no_difference("ActiveStorage::Attachment.count") do
      post job_attachments_url(@job), params: { job: { files: [ upload ] } }
      assert_redirected_to new_session_url
      delete job_attachment_url(@job, file)
      assert_redirected_to new_session_url
    end
  end

  test "empty uploads and signed blob ids are rejected" do
    @job.files.attach(upload)
    [ [], [ "" ], [ @job.files.first.blob.signed_id ] ].each do |files|
      assert_no_difference("ActiveStorage::Attachment.count") do
        post job_attachments_url(@job), params: { job: { files: files } }
      end
      assert_response :unprocessable_entity
      assert_select "[role='alert']", text: /at least one uploaded file/
    end
  end

  test "oversized upload rejects entire batch and preserves existing attachments" do
    @job.files.attach(upload)
    oversized = upload
    oversized.tempfile.truncate(Job::MAX_FILE_SIZE + 1)
    assert_no_difference([ "ActiveStorage::Attachment.count", "ActiveStorage::Blob.count" ]) do
      post job_attachments_url(@job), params: { job: { files: [ upload, oversized ] } }
    end
    assert_response :unprocessable_entity
    assert_select "[role='alert']", text: /20 MB or smaller/
    assert_equal 1, @job.reload.files.count
  end

  test "default public storage routes are disabled" do
    assert_raises(ActionController::RoutingError) do
      Rails.application.routes.recognize_path("/rails/active_storage/blobs/redirect/token/project.txt")
    end
  end

  private
    def upload
      fixture_file_upload("project.txt", "text/plain")
    end
end
