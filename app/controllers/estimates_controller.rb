class EstimatesController < ApplicationController
  before_action :set_job
  before_action :set_estimate, only: %i[show edit update mark_sent approve reject]

  before_action :require_editable_estimate, only: %i[edit update]

  def show
    respond_to do |format|
      format.html
      format.pdf do
        send_data EstimatePdf.new(@estimate).render,
          filename: "estimate-#{@estimate.id}-job-#{@job.id}.pdf",
          type: "application/pdf", disposition: "attachment"
      end
    end
  end

  def new
    if @job.estimate.present?
      redirect_to job_estimate_path(@job)
      return
    end

    @estimate = @job.build_estimate
    @estimate.estimate_line_items.build(quantity: nil)
  end

  def create
    if @job.estimate.present?
      redirect_to job_estimate_path(@job)
      return
    end

    @estimate = @job.build_estimate(estimate_params)

    saved = Estimate.transaction do
      success = @estimate.save

      if success
        @job.activities.create!(actor: Current.user, event: "estimate_created",
          metadata: { estimate_id: @estimate.id, new_status: @estimate.status,
                      total: @estimate.total.to_d.to_s("F"), line_item_count: @estimate.estimate_line_items.size })
      end

      success
    end

    if saved
      redirect_to job_estimate_path(@job), notice: "Estimate was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @estimate.update(estimate_params)
      redirect_to job_estimate_path(@job), notice: "Estimate was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def mark_sent
    update_status("sent")
  end

  def approve
    update_status("approved")
  end

  def reject
    update_status("rejected")
  end

  private
    def require_editable_estimate
      if @estimate.status == "approved"
        redirect_to job_estimate_path(@job),
          alert: "Approved estimates cannot be edited. Mark the estimate as sent or rejected before editing.",
          status: :see_other
      end
    end

    def update_status(status)
      updated = @estimate.with_lock do
        success = @estimate.update(status: status)

        if success && @estimate.saved_change_to_status?
          previous_status, new_status = @estimate.saved_change_to_status
          @job.activities.create!(actor: Current.user, event: "estimate_status_changed",
            metadata: { estimate_id: @estimate.id, previous_status: previous_status, new_status: new_status,
                        total: @estimate.total.to_d.to_s("F"), line_item_count: @estimate.estimate_line_items.size })
        end

        success
      end

      if updated
        redirect_to job_estimate_path(@job), notice: "Estimate marked as #{status}.", status: :see_other
      else
        flash.now[:alert] = @estimate.errors.full_messages.to_sentence
        render :show, status: :unprocessable_entity
      end
    end

    def set_job
      @job = Current.user.jobs.find(params[:job_id])
    end

    def set_estimate
      @estimate = @job.estimate
      raise ActiveRecord::RecordNotFound unless @estimate
    end

    def estimate_params
      params.expect(estimate: [
        :notes,
        :expires_on,
        estimate_line_items_attributes: [ [
          :id,
          :description,
          :quantity,
          :unit_price,
          :_destroy
        ] ]
      ])
    end
end
