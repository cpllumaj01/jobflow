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
    assert_select "ul[aria-label='Customers'] li", count: 1 do
      assert_select "h2", @customer.name
      assert_select "dd", @customer.contact_name
      assert_select "dd", @customer.email
      assert_select "a[href=?][aria-label=?]", customer_path(@customer), "View #{@customer.name}"
    end
  end

  test "mobile customer records display placeholders for missing contact details" do
    @customer.update!(contact_name: nil, email: nil, address: nil)

    get customers_url

    assert_response :success
    assert_select "ul[aria-label='Customers'] li" do
      assert_select "h2", @customer.name
      assert_select "dd", text: "—", count: 2
      assert_select "p", count: 0
    end
  end

  test "pagination orders customers by name and breaks ties by id across pages" do
    @customer.update!(name: "Z customer")
    added_customers = Array.new(50) { @user.customers.create!(name: "A customer") }

    get customers_url
    assert_select "tbody a" do |links|
      assert_equal added_customers.first(25).map { |customer| customer_path(customer) }, links.map { |link| link["href"] }
    end
    assert_select "nav[aria-label='Pagination']" do
      assert_select "p", text: /Showing 1–25 of 51\s+Page 1 of 3/
      assert_select "span[aria-disabled='true']", text: "Previous"
    end

    get css_select("a[rel='next']").first["href"]
    assert_select "tbody a" do |links|
      assert_equal added_customers.last(25).map { |customer| customer_path(customer) }, links.map { |link| link["href"] }
    end
    assert_select "nav[aria-label='Pagination'] p", text: /Showing 26–50 of 51\s+Page 2 of 3/

    get css_select("a[rel='next']").first["href"]
    assert_select "tbody a", count: 1
    assert_select "tbody a[href=?]", customer_path(@customer)
    assert_select "nav[aria-label='Pagination']" do
      assert_select "p", text: /Showing 51–51 of 51\s+Page 3 of 3/
      assert_select "span[aria-disabled='true']", text: "Next"
      assert_select "a[rel='next']", count: 0
    end

    get css_select("a[rel='prev']").first["href"]
    assert_select "nav[aria-label='Pagination'] p", text: /Page 2 of 3/
    assert_select "tbody a[href=?]", customer_path(customers(:fairfield)), count: 0
  end

  test "invalid pages use the first page and excessive pages use the last owned page" do
    25.times { @user.customers.create!(name: "A customer") }

    [ "invalid", "", "0", "-1", "1.5", "2oops", [ "2" ], { number: "2" } ].each do |page|
      get customers_url, params: { page: page }

      assert_response :success
      assert_select "tbody tr", count: 25
      assert_select "nav[aria-label='Pagination'] p", text: /Page 1 of 2/
    end

    get customers_url, params: { page: "9" * 100 }
    assert_response :success
    assert_select "tbody tr", count: 1
    assert_select "tbody a[href=?]", customer_path(@customer)
    assert_select "nav[aria-label='Pagination'] p", text: /Page 2 of 2/
  end

  test "single and empty pages have no pagination links" do
    get customers_url
    assert_select "nav[aria-label='Pagination'] p", text: /Showing 1–1 of 1\s+Page 1 of 1/
    assert_select "nav[aria-label='Pagination'] a", count: 0

    @customer.destroy!
    get customers_url, params: { page: 999 }
    assert_response :success
    assert_select "h2", "No customers yet"
    assert_select "nav[aria-label='Pagination']", count: 0
  end

  test "an exact full page does not offer an empty next page" do
    24.times { @user.customers.create!(name: "A customer") }

    get customers_url
    assert_select "tbody tr", count: 25
    assert_select "nav[aria-label='Pagination'] p", text: /Showing 1–25 of 25\s+Page 1 of 1/
    assert_select "nav[aria-label='Pagination'] a", count: 0
  end

  test "pagination only instantiates one page of customers" do
    30.times { @user.customers.create!(name: "A customer") }
    instantiated = 0
    subscriber = ->(event) { instantiated += event.payload[:record_count] if event.payload[:class_name] == "Customer" }

    ActiveSupport::Notifications.subscribed(subscriber, "instantiation.active_record") do
      get customers_url
    end

    assert_response :success
    assert_equal 25, instantiated
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
    assert_select "h3", text: "No jobs yet", count: 0
  end

  test "show guides a customer without jobs to the existing new job action" do
    customer = @user.customers.create!(name: "New customer")

    get customer_url(customer)

    assert_response :success
    assert_select "h3", "No jobs yet"
    assert_select "p", "Create a job for this customer to track work, estimates, and change orders."
    assert_select "a[href=?]", new_job_path(customer_id: customer.id), text: "New job", count: 1
  end

  test "show does not display another customer's jobs" do
    get customer_url(@customer)

    assert_select "body", text: /Office Buildout/, count: 0
  end
end
