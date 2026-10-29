class JobsController < ApplicationController
  before_action :set_job, only: %i[show edit update update_status destroy]
  before_action :set_customers, only: %i[new edit create update]

  def index
    @query = params[:q].to_s.strip
    @status = params[:status].to_s
    @jobs = Current.user.jobs.order(created_at: :desc, id: :desc)

    if @query.present?
      pattern = "%#{Job.sanitize_sql_like(@query)}%"
      @jobs = @jobs.joins(:customer).where(
        "jobs.name ILIKE :query OR jobs.address ILIKE :query OR customers.name ILIKE :query",
        query: pattern
      )
    end

    if @status.present?
      @jobs = Job::STATUSES.include?(@status) ? @jobs.where(status: @status) : @jobs.none
    end

    @jobs = paginate(@jobs).includes(:customer).load
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
    customer_id = attributes.delete(:customer_id)
    @job = Job.new(attributes)
    @job.customer = Current.user.customers.find(customer_id) if customer_id.present?

    if @job.save
      redirect_to @job, notice: "Job was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    attributes = job_params
    customer = Current.user.customers.find(attributes.delete(:customer_id))

    if update_job(attributes.merge(customer: customer))
      redirect_to @job, notice: "Job was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def update_status
    if update_job(params.expect(job: [ :status ]))
      redirect_to @job, notice: "Job status was successfully updated.", status: :see_other
    else
      flash.now[:alert] = @job.errors.full_messages.to_sentence
      @job.reload
      render :show, status: :unprocessable_entity
    end
  end

  def destroy
    @job.destroy!

    redirect_to jobs_path, notice: "Job was successfully deleted.", status: :see_other
  end

  private
    def update_job(attributes)
      @job.with_lock do
        success = @job.update(attributes)

        if success && @job.saved_change_to_status?
          previous_status, new_status = @job.saved_change_to_status
          metadata = { previous_status: previous_status, new_status: new_status }
          metadata[:completed_at] = @job.completed_at.iso8601(6) if new_status == "completed"
          previous_completed_at = @job.saved_change_to_completed_at&.first
          if previous_status == "completed" && previous_completed_at
            metadata[:previous_completed_at] = previous_completed_at.iso8601(6)
          end
          @job.activities.create!(actor: Current.user, event: "job_status_changed", metadata: metadata)
        end

        success
      end
    end

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
        :estimated_completion_date
      ])
    end
end
