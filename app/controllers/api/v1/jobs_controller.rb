class Api::V1::JobsController < ApplicationController
  rescue_from ActiveRecord::RecordNotFound do
    render json: { error: "Job not found" }, status: :not_found
  end

  def index
    render json: { jobs: owned_jobs.order(created_at: :desc, id: :desc).map { |job| job_json(job) } }
  end

  def show
    job = owned_jobs.find(params[:id])
    render json: { job: job_json(job).merge(
      estimate: job.estimate && {
        id: job.estimate.id, status: job.estimate.status, total: job.estimate.total.to_d.to_s("F")
      },
      change_orders: job.change_orders.map do |change_order|
        { id: change_order.id, title: change_order.title, status: change_order.status,
          total: change_order.total.to_d.to_s("F") }
      end
    ) }
  end

  private
    def owned_jobs
      Current.user.jobs.includes(:customer, estimate: :estimate_line_items, change_orders: :change_order_line_items)
    end

    def job_json(job)
      {
        id: job.id,
        name: job.name,
        address: job.address,
        status: job.status,
        created_at: job.created_at,
        updated_at: job.updated_at,
        customer: { id: job.customer.id, name: job.customer.name },
        original_estimate_value: job.original_estimate_value.to_d.to_s("F"),
        approved_change_order_total: job.approved_change_order_total.to_d.to_s("F"),
        current_contract_value: job.current_contract_value.to_d.to_s("F")
      }
    end
end
