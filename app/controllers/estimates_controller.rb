class EstimatesController < ApplicationController
  before_action :set_job
  before_action :set_estimate, only: %i[show edit update mark_sent approve reject]

  before_action :require_editable_estimate, only: %i[edit update]

  def show
  end

  def new
    if @job.estimate.present?
      redirect_to job_estimate_path(@job)
      return
    end

    @estimate = @job.build_estimate
    build_blank_line_items
  end

  def create
    if @job.estimate.present?
      redirect_to job_estimate_path(@job)
      return
    end

    @estimate = @job.build_estimate(estimate_params)

    if @estimate.save
      redirect_to job_estimate_path(@job), notice: "Estimate was successfully created."
    else
      build_blank_line_items
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    build_blank_line_items
  end

  def update
    if @estimate.update(estimate_params)
      redirect_to job_estimate_path(@job), notice: "Estimate was successfully updated."
    else
      build_blank_line_items
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
      if @estimate.update(status: status)
        redirect_to job_estimate_path(@job), notice: "Estimate marked as #{status}.", status: :see_other
      else
        flash.now[:alert] = @estimate.errors.full_messages.to_sentence
        render :show, status: :unprocessable_entity
      end
    end

    def build_blank_line_items
      3.times { @estimate.estimate_line_items.build(quantity: nil) }
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
        estimate_line_items_attributes: [[
          :id,
          :description,
          :quantity,
          :unit_price,
          :_destroy
        ]]
      ])
    end
end
