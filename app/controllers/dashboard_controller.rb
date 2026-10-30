class DashboardController < ApplicationController
  def index
    jobs = Current.user.jobs

    @total_customers = Current.user.customers.count
    @jobs_by_status = jobs.group(:status).count
    @total_jobs = @jobs_by_status.values.sum
    @active_jobs = @jobs_by_status.values_at("approved", "in_progress").compact.sum
    @pending_estimates = Estimate.where(job_id: jobs.select(:id), status: "sent").count
    @pending_change_orders = ChangeOrder.where(job_id: jobs.select(:id), status: "pending").count
    financial_jobs = jobs.includes(
      estimate: :estimate_line_items,
      change_orders: :change_order_line_items
    ).load
    @approved_estimate_value = financial_jobs.sum(&:original_estimate_value)
    @approved_change_order_value = financial_jobs.sum(&:approved_change_order_total)
    @total_current_contract_value = @approved_estimate_value + @approved_change_order_value
  end
end
