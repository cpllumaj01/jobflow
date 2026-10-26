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
      @job.with_lock do
        existing_ids = @job.files.ids
        if @job.files.attach(uploads)
          @job.files_attachments.includes(:blob).where.not(id: existing_ids).each do |attachment|
            @job.activities.create!(actor: Current.user, event: "attachment_added",
              metadata: { attachment_id: attachment.id, filename: attachment.filename.to_s })
          end
        end
      end
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
    blob = nil
    @job.with_lock do
      attachment = @job.files.find(params[:id])
      blob = attachment.blob
      attachment.delete
      @job.touch
      @job.activities.create!(actor: Current.user, event: "attachment_removed",
        metadata: { attachment_id: attachment.id, filename: blob.filename.to_s })
    end
    # Keep storage deletion outside the transaction, after the removal and history commit.
    blob.purge
    redirect_to @job, notice: "Attachment was successfully removed.", status: :see_other
  end

  private
    def set_job
      @job = Current.user.jobs.find(params[:job_id])
    end
end
