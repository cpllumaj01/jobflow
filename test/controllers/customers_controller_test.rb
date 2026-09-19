require "test_helper"

class CustomersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @customer = customers(:johnson)

    sign_in_as @user
  end

  test "should get index" do
    get customers_url

    assert_response :success
    assert_select "body", text: /Johnson Residence/
    assert_select "body", text: /Fairfield Construction LLC/, count: 0
  end

  test "should get new" do
    get new_customer_url

    assert_response :success
  end

  test "should create customer" do
    assert_difference("Customer.count") do
      post customers_url, params: {
        customer: {
          name: "Smith Residence",
          contact_name: "John Smith",
          email: "john@example.com",
          phone: "203-555-0103",
          address: "789 Main Street",
          notes: "Bathroom remodel"
        }
      }
    end

    customer = Customer.find_by!(name: "Smith Residence")

    assert_equal @user, customer.user
    assert_redirected_to customer_url(customer)
  end

  test "should show customer" do
    get customer_url(@customer)

    assert_response :success
  end

  test "should get edit" do
    get edit_customer_url(@customer)

    assert_response :success
  end

  test "should update customer" do
    patch customer_url(@customer), params: {
      customer: {
        name: "Johnson Family Residence"
      }
    }

    assert_redirected_to customer_url(@customer)
    assert_equal "Johnson Family Residence", @customer.reload.name
  end

  test "should destroy customer" do
    assert_difference("Customer.count", -1) do
      delete customer_url(@customer)
    end

    assert_redirected_to customers_url
  end

  test "cannot access another user's customer" do
    get customer_url(customers(:fairfield))

    assert_response :not_found
  end

  test "cannot destroy another user's customer" do
    assert_no_difference("Customer.count") do
      delete customer_url(customers(:fairfield))
    end

    assert_response :not_found
  end

  test "show displays customer's jobs" do
    get customer_url(@customer)

    assert_response :success
    assert_select "body", text: /Kitchen Renovation/
  end

  test "show does not display another customer's jobs" do
    get customer_url(@customer)

    assert_select "body", text: /Office Buildout/, count: 0
  end

end
