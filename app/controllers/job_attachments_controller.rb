class JobAttachmentsController < ApplicationController
  before_action :set_job

  def show
    attachment = @job.files.find(params[:id])
    send_data attachment.download, filename: attachment.filename.to_s,
      type: attachment.content_type, disposition: "attachment"
  end

  def create
    uploads = Array(params.dig(:job, :files)).reject(&:blank?)

    if uploads.empty? || uploads.any? { |file| !file.is_a?(ActionDispatch::Http::UploadedFile) }
      @job.errors.add(:files, "must include at least one uploaded file")
    else
      @job.files.attach(uploads)
    end

    if @job.errors.empty?
      redirect_to @job, notice: "Files were successfully uploaded.", status: :see_other
    else
      @attachment_errors = @job.errors.full_messages
      @job.reload
      render "jobs/show", status: :unprocessable_entity
    end
  end

  def destroy
    @job.files.find(params[:id]).purge
    redirect_to @job, notice: "Attachment was successfully removed.", status: :see_other
  end

  private
    def set_job
      @job = Current.user.jobs.find(params[:job_id])
    end
end
