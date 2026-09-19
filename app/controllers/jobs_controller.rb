class JobsController < ApplicationController
  before_action :set_job, only: %i[show edit update destroy]
  before_action :set_customers, only: %i[new edit create update]

  def index
    @jobs = Current.user.jobs.includes(:customer).order(created_at: :desc)
  end

  def show
  end

  def new
    @job = Job.new

    if params[:customer_id].present?
      @job.customer = Current.user.customers.find(params[:customer_id])
    end
  end

  def edit
  end

  def create
    attributes = job_params
    customer = Current.user.customers.find(attributes.delete(:customer_id))
    @job = customer.jobs.new(attributes)

    if @job.save
      redirect_to @job, notice: "Job was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    attributes = job_params
    @job.customer = Current.user.customers.find(attributes.delete(:customer_id))

    if @job.update(attributes)
      redirect_to @job, notice: "Job was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @job.destroy!

    redirect_to jobs_path, notice: "Job was successfully deleted.", status: :see_other
  end

  private
    def set_job
      @job = Current.user.jobs.find(params[:id])
    end

    def set_customers
      @customers = Current.user.customers.order(:name)
    end

    def job_params
      params.expect(job: [
        :customer_id,
        :name,
        :description,
        :address,
        :status,
        :start_date,
        :estimated_completion_date,
        :completed_at
      ])
    end
end
