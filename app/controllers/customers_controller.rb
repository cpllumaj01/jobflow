class CustomersController < ApplicationController
  before_action :set_customer, only: %i[show edit update destroy]

  def index
    @customers = Current.user.customers.order(:name)
  end

  def show
  end

  def new
    @customer = Current.user.customers.new
  end

  def edit
  end

  def create
    @customer = Current.user.customers.new(customer_params)

    if @customer.save
      redirect_to @customer, notice: "Customer was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @customer.update(customer_params)
      redirect_to @customer, notice: "Customer was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @customer.destroy!

    redirect_to customers_path, notice: "Customer was successfully deleted.", status: :see_other
  end

  private
    def set_customer
      @customer = Current.user.customers.find(params[:id])
    end

    def customer_params
      params.expect(customer: [:name, :contact_name, :email, :phone, :address, :notes])
    end
end
