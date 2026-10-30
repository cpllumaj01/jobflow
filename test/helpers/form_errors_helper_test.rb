require "test_helper"

class FormErrorsHelperTest < ActionView::TestCase
  test "inline messages are escaped deduplicated and do not announce separately" do
    customer = Customer.new
    2.times { customer.errors.add(:name, "must not contain <script>alert('x')</script>") }
    form = ActionView::Helpers::FormBuilder.new(:customer, customer, self, {})

    fragment = Nokogiri::HTML.fragment(field_errors(form, :name))
    assert_equal "Name must not contain <script>alert('x')</script>", fragment.text
    assert_equal "customer_name_error", fragment.at_css("p")["id"]
    assert_nil fragment.at_css("script, [role], [aria-live]")
    assert_nil field_errors(form, :notes)
  end

  test "invalid date keeps help text associated and renders errors immediately beneath the input" do
    @customers = [ customers(:johnson) ]
    job = Job.new
    job.errors.add(:estimated_completion_date, "must be after the start date")
    render "jobs/form", job: job

    assert_select '#job_estimated_completion_date[aria-invalid="true"][aria-describedby="estimated-completion-help job_estimated_completion_date_error"]'
    assert_select ".field_with_errors + #job_estimated_completion_date_error", text: "Estimated completion date must be after the start date"
    assert_select "#estimated-completion-help", count: 1
    assert_select "#job_start_date:not([aria-invalid]):not([aria-describedby])"
  end

  test "summary keeps base cross-field and unmapped nested errors without repeating inline messages" do
    estimate = Estimate.new
    estimate.errors.add(:base, "Dates overlap another estimate")
    estimate.errors.add(:status, "cannot be changed")
    estimate.errors.add(:"estimate_line_items.base", "Some items cannot be combined")
    estimate.errors.add(:"estimate_line_items.quantity", "must be greater than 0")
    render "shared/form_errors", record: estimate, inline_fields: %w[estimate_line_items.quantity]

    assert_select '[role="alert"]', count: 1 do
      assert_select "li", count: 3
      assert_select "li", text: "Dates overlap another estimate"
      assert_select "li", text: "Status cannot be changed"
      assert_select "li", text: /Some items cannot be combined/
      assert_select "li", text: /greater than 0/, count: 0
    end
  end
end
