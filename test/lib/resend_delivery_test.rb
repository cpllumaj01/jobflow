require "test_helper"

class ResendDeliveryTest < ActionMailer::TestCase
  setup do
    @original_api_key = Resend.api_key
    Resend.api_key = "test-only-key"
  end

  teardown { Resend.api_key = @original_api_key }

  test "official integration delivers multipart mail over HTTPS with authentication" do
    delivery = PasswordsMailer.reset(users(:one))
    mail = delivery.message
    mail.delivery_method(ActionMailer::Base.delivery_methods.fetch(:resend))
    with_http_response({ id: "provider-message-id" }) do |request|
      delivery.deliver_now
      url, options = request.call
      assert_equal "https://api.resend.com/emails", url
      assert_equal "Bearer test-only-key", options[:headers]["Authorization"]
      assert options[:headers]["Idempotency-Key"].present?
      payload = JSON.parse(options[:body])
      assert_equal mail[:from].formatted.first, payload["from"]
      assert_equal mail.to, payload["to"]
      assert_equal mail.subject, payload["subject"]
      assert_equal mail.html_part.body.decoded, payload["html"]
      assert_equal mail.text_part.body.decoded, payload["text"]
      assert_equal "provider-message-id", mail.message_id
    end
  end

  test "provider errors propagate without including response text or an unsafe cause" do
    delivery = PasswordsMailer.reset(users(:one))
    delivery.message.delivery_method(ActionMailer::Base.delivery_methods.fetch(:resend))
    with_http_response({ statusCode: 401, message: "private-provider-response test-only-key private-token" }) do
      error = assert_raises(Resend::Error) { delivery.deliver_now }
      assert_instance_of Resend::Error::InvalidRequestError, error
      assert_equal "Resend delivery failed (Resend::Error::InvalidRequestError)", error.message
      %w[private-provider-response test-only-key private-token].each do |sensitive|
        refute_includes error.full_message, sensitive
      end
      assert_nil error.cause
    end
  end

  test "rate limit errors include only the class and numeric retry delay" do
    delivery = PasswordsMailer.reset(users(:one))
    delivery.message.delivery_method(ActionMailer::Base.delivery_methods.fetch(:resend))
    with_http_response(
      { statusCode: 429, message: "private-provider-response test-only-key private-token" },
      headers: { "retry-after" => "42", "private-header" => "private-header-value" }
    ) do
      error = assert_raises(Resend::Error::RateLimitExceededError) { delivery.deliver_now }
      assert_instance_of Resend::Error::RateLimitExceededError, error
      assert_equal "Resend delivery failed (Resend::Error::RateLimitExceededError); retry after 42s", error.message
      assert_nil error.cause
      %w[private-provider-response test-only-key private-token private-header-value].each do |sensitive|
        refute_includes error.full_message, sensitive
      end
      assert_empty error.headers
    end
  end

  test "rate limit errors without a retry delay include only the class" do
    delivery = PasswordsMailer.reset(users(:one))
    delivery.message.delivery_method(ActionMailer::Base.delivery_methods.fetch(:resend))
    with_http_response({ statusCode: 429, message: "private-provider-response" }) do
      error = assert_raises(Resend::Error::RateLimitExceededError) { delivery.deliver_now }
      assert_instance_of Resend::Error::RateLimitExceededError, error
      assert_equal "Resend delivery failed (Resend::Error::RateLimitExceededError)", error.message
      assert_nil error.cause
      refute_includes error.full_message, "private-provider-response"
    end
  end

  test "missing credentials fail before contacting the provider" do
    Resend.api_key = nil
    assert_raises(Resend::Error) { ResendDelivery.new({}) }
  end

  test "network failures propagate to the delivery job" do
    with_http_response(Net::ReadTimeout.new) do
      assert_raises(Net::ReadTimeout) do
        ResendDelivery.new({}).deliver!(PasswordsMailer.reset(users(:one)).message)
      end
    end
  end

  private
    # Exercise the SDK while replacing its HTTP boundary; no real email is sent.
    def with_http_response(data, headers: {})
      original = HTTParty.method(:post)
      captured_request = nil
      response = Struct.new(:body, :parsed_response, :headers).new(JSON.generate(data), data.transform_keys(&:to_s), headers) unless data.is_a?(Exception)
      HTTParty.define_singleton_method(:post) do |url, options|
        captured_request = [ url, options ]
        raise data if data.is_a?(Exception)
        response
      end
      yield -> { captured_request }
    ensure
      HTTParty.define_singleton_method(:post, original)
    end
end
