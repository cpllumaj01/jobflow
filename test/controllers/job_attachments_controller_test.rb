require "test_helper"

class JobAttachmentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @job = jobs(:kitchen_renovation)
    sign_in_as users(:one)
  end

  test "uploads multiple files and appends subsequent uploads" do
    assert_difference([ "ActiveStorage::Attachment.count", "ActiveStorage::Blob.count", "Activity.count" ], 2) do
      post job_attachments_url(@job), params: { job: { files: [ upload, upload ] } }
    end
    assert_redirected_to job_url(@job)
    assert_difference("Activity.count", 1) do
      post job_attachments_url(@job), params: { job: { files: [ upload ] } }
    end
    assert_equal 3, @job.files.count
    @job.activities.each do |activity|
      assert_equal "attachment_added", activity.event
      assert_equal users(:one), activity.actor
      assert_equal "project.txt", activity.metadata["filename"]
      assert_includes @job.files.ids, activity.metadata["attachment_id"]
    end

    get job_url(@job)
    assert_response :success
    assert_select "p", text: /No attachments yet/, count: 0
    @job.files.each do |file|
      assert_select "a[href=?]", job_attachment_path(@job, file), text: "project.txt"
    end
  end

  test "empty job displays upload form and empty state" do
    get job_url(@job)
    assert_select "p", text: "No attachments yet. Upload plans, photos, or documents using the form below."
    assert_select "form[action=?][enctype='multipart/form-data']", job_attachments_path(@job), count: 1 do
      assert_select "input[type='file'][multiple][name='job[files][]']"
      assert_select "input[type='file'][aria-describedby='file-size-limit file-upload-errors']"
      assert_select "[data-attachment-upload-max-size-value=?]", Job::MAX_FILE_SIZE.to_s
      assert_select "#file-size-limit", text: /PDF, JPG\/JPEG, PNG, WEBP, TXT, CSV, DOCX, XLSX.*20 MB per file/
      assert_select "#file-upload-errors[role='alert'][aria-atomic='true']"
      assert_select "input[type='submit'][value='Upload files']", count: 1
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
      assert_difference("Activity.count", 1) do
        assert_difference("ActiveStorage::Attachment.count", -1) do
          delete job_attachment_url(@job, file)
        end
      end
    end
    assert_redirected_to job_url(@job)
    assert_equal 1, @job.reload.files.count
    assert_not ActiveStorage::Blob.exists?(blob.id)
    assert_not blob.service.exist?(blob.key)
    activity = @job.activities.sole
    assert_equal "attachment_removed", activity.event
    assert_equal users(:one), activity.actor
    assert_equal({ "attachment_id" => file.id, "filename" => "project.txt" }, activity.metadata)
    assert_no_difference("Activity.count") { delete job_attachment_url(@job, file) }
    assert_response :not_found
  end

  test "cannot upload to another users job" do
    assert_no_difference([ "ActiveStorage::Attachment.count", "ActiveStorage::Blob.count", "Activity.count" ]) do
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
      assert_no_difference([ "ActiveStorage::Attachment.count", "Activity.count" ]) do
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
    assert_no_difference([ "ActiveStorage::Attachment.count", "Activity.count" ]) do
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
    assert_no_difference([ "ActiveStorage::Attachment.count", "ActiveStorage::Blob.count", "Activity.count" ]) do
      post job_attachments_url(@job), params: { job: { files: [ upload ] } }
      assert_redirected_to new_session_url
      delete job_attachment_url(@job, file)
      assert_redirected_to new_session_url
    end
  end

  test "missing malformed uploads and signed blob ids reject the entire batch" do
    @job.files.attach(upload)
    [ {}, { job: "invalid" }, { job: {} }, { job: { files: {} } },
      { job: { files: { filename: "plan.pdf" } } },
      { job: { files: [] } }, { job: { files: [ "" ] } },
      { job: { files: [ upload, @job.files.first.blob.signed_id ] } },
      { job: { files: [ upload, "invalid" ] } } ].each do |parameters|
      assert_rejected_batch(parameters, /at least one uploaded file/)
    end
  end

  test "upload exactly at the size limit is accepted with intact content" do
    contents = "a" * Job::MAX_FILE_SIZE
    assert_difference([ "ActiveStorage::Attachment.count", "ActiveStorage::Blob.count", "Activity.count" ], 1) do
      post job_attachments_url(@job), params: { job: { files: [ upload_with(contents, filename: "scope.txt") ] } }
    end
    assert_redirected_to job_url(@job)
    assert_equal Job::MAX_FILE_SIZE, @job.files.sole.byte_size
    assert_equal contents, @job.files.sole.download
  end

  test "supported document image and text formats accept untrustworthy client MIME types" do
    %w[plan.pdf photo.jpg photo.png photo.webp materials.csv project.docx project.xlsx project.txt].each do |filename|
      file = fixture_file_upload(filename, "application/octet-stream")
      assert_difference([ "ActiveStorage::Attachment.count", "ActiveStorage::Blob.count", "Activity.count" ], 1) do
        post job_attachments_url(@job), params: { job: { files: [ file ] } }
      end
      assert_redirected_to job_url(@job)
      attachment = @job.files.order(:id).last
      assert_equal Job::FILE_CONTENT_TYPES[File.extname(filename).delete_prefix(".")], attachment.content_type
      assert_equal File.binread(file_fixture(filename)), attachment.download
    end

    file = upload_with(File.binread(file_fixture("photo.png")), filename: "PHOTO.PNG", type: "application/pdf")
    post job_attachments_url(@job), params: { job: { files: [ file ] } }
    assert_redirected_to job_url(@job)
    assert_equal "image/png", @job.files.order(:id).last.content_type

    file = upload_with(File.binread(file_fixture("photo.jpg")), filename: "photo.jpeg", type: "text/plain")
    post job_attachments_url(@job), params: { job: { files: [ file ] } }
    assert_redirected_to job_url(@job)
    assert_equal "image/jpeg", @job.files.order(:id).last.content_type
  end

  test "UTF-8 text with a BOM or non-ASCII characters is accepted" do
    contents = "\uFEFFScope: café renovation\n"
    post job_attachments_url(@job), params: { job: { files: [ upload_with(contents, filename: "scope.txt") ] } }
    assert_redirected_to job_url(@job)
    assert_equal contents.b, @job.files.sole.download
  end

  test "unsupported extensions and mismatched or binary content reject the entire batch" do
    @job.files.attach(upload)
    [ [ "program.exe", "MZ\x90\0", "application/pdf" ],
      [ "scope.html", "<html><script>alert(1)</script></html>", "text/plain" ],
      [ "scope.svg", '<svg xmlns="http://www.w3.org/2000/svg"/>', "image/svg+xml" ],
      [ "scope.docm", File.binread(file_fixture("project.docx")), "application/vnd.openxmlformats-officedocument.wordprocessingml.document" ],
      [ "scope", "project notes", "text/plain" ],
      [ "fake.pdf", "project notes", "application/pdf" ],
      [ "photo.jpg", File.binread(file_fixture("plan.pdf")), "image/jpeg" ],
      [ "scope.txt", "<html><script>alert(1)</script></html>", "text/plain" ],
      [ "scope.txt", "binary\0content", "text/plain" ],
      [ "materials.csv", "\xFF\xFE\0\0", "text/csv" ],
      [ "project.docx", File.binread(file_fixture("project.xlsx")), "application/vnd.openxmlformats-officedocument.wordprocessingml.document" ],
      [ "fake.xlsx", "PK\x03\x04" + ("\0" * 100), "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" ] ].each do |filename, contents, type|
      bad_file = upload_with(contents, filename: filename, type: type)
      assert_rejected_batch({ job: { files: [ upload, bad_file ] } }, /#{Regexp.escape(filename)}.*unsupported format/)
    end
  end

  test "empty file rejects a mixed batch" do
    @job.files.attach(upload)
    assert_rejected_batch({ job: { files: [ upload, upload_with("", filename: "empty.txt") ] } }, /empty.txt.*is empty/)
  end

  test "oversized upload rejects entire batch and preserves existing attachments" do
    @job.files.attach(upload)
    oversized = upload
    oversized.tempfile.truncate(Job::MAX_FILE_SIZE + 1)
    assert_rejected_batch({ job: { files: [ upload, oversized ] } }, /project.txt.*20 MB or smaller/)
  end

  test "default public storage routes are disabled" do
    assert_raises(ActionController::RoutingError) do
      Rails.application.routes.recognize_path("/rails/active_storage/blobs/redirect/token/project.txt")
    end
  end

  private
    def assert_rejected_batch(parameters, message)
      existing_ids = @job.files.ids
      assert_no_difference([ "ActiveStorage::Attachment.count", "ActiveStorage::Blob.count", "Activity.count" ]) do
        post job_attachments_url(@job), params: parameters
      end
      assert_response :unprocessable_entity
      assert_select "[role='alert']", text: message
      assert_equal existing_ids, @job.reload.files.ids
      @job.files.each { |file| assert_equal File.read(file_fixture("project.txt")), file.download }
    end

    def upload_with(contents, filename:, type: "text/plain")
      Rack::Test::UploadedFile.new(StringIO.new(contents.b), type, true, original_filename: filename)
    end

    def upload
      fixture_file_upload("project.txt", "text/plain")
    end
end
