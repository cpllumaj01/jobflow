class ChangeOrdersController < ApplicationController
  before_action :set_job
  before_action :set_change_order, only: %i[show edit update mark_pending approve reject]
  before_action :require_editable_change_order, only: %i[edit update]

  def index
    @change_orders = @job.change_orders.order(created_at: :desc)
  end

  def show
  end

  def new
    @change_order = @job.change_orders.new
    build_blank_line_items
  end

  def create
    @change_order = @job.change_orders.new(change_order_params)

    if @change_order.save
      redirect_to job_change_order_path(@job, @change_order), notice: "Change order was successfully created."
    else
      build_blank_line_items
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    build_blank_line_items
  end

  def update
    if @change_order.update(change_order_params)
      redirect_to job_change_order_path(@job, @change_order), notice: "Change order was successfully updated."
    else
      build_blank_line_items
      render :edit, status: :unprocessable_entity
    end
  end

  def mark_pending
    update_status("pending")
  end

  def approve
    update_status("approved")
  end

  def reject
    update_status("rejected")
  end

  private
    def update_status(status)
      if @change_order.update(status: status)
        redirect_to job_change_order_path(@job, @change_order), notice: "Change order marked as #{status}.", status: :see_other
      else
        flash.now[:alert] = @change_order.errors.full_messages.to_sentence
        render :show, status: :unprocessable_entity
      end
    end

    def set_job
      @job = Current.user.jobs.find(params[:job_id])
    end

    def set_change_order
      @change_order = @job.change_orders.find(params[:id])
    end

    def require_editable_change_order
      if @change_order.status == "approved"
        redirect_to job_change_order_path(@job, @change_order),
          alert: "Approved change orders cannot be edited. Mark the change order as pending or rejected before editing.", status: :see_other
      end
    end

    def build_blank_line_items
      3.times { @change_order.change_order_line_items.build(quantity: nil) }
    end

    def change_order_params
      params.expect(change_order: [
        :title,
        :description,
        change_order_line_items_attributes: [[
          :id,
          :description,
          :quantity,
          :unit_price,
          :_destroy
        ]]
      ])
    end
end
