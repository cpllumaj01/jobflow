class DashboardController < ApplicationController
  def index
    jobs = Current.user.jobs

    @total_customers = Current.user.customers.count
    @total_jobs = jobs.count
    @active_jobs = jobs.where(status: %w[approved in_progress]).count
    @pending_estimates = Estimate.where(job_id: jobs.select(:id), status: "sent").count
    @pending_change_orders = ChangeOrder.where(job_id: jobs.select(:id), status: "pending").count
    @total_current_contract_value = jobs.includes(
      estimate: :estimate_line_items,
      change_orders: :change_order_line_items
    ).sum(&:current_contract_value)
  end
end
