class EstimatesController < ApplicationController
  before_action :set_job
  before_action :set_estimate, only: %i[show edit update]

  def show
  end

  def new
    if @job.estimate.present?
      redirect_to job_estimate_path(@job)
      return
    end

    @estimate = @job.build_estimate
    @estimate.estimate_line_items.build
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

  private
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
