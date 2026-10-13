require "test_helper"

class PasswordResetDeliveryJobTest < ActiveJob::TestCase
  setup do
    @user = users(:one)
    @original_api_key = Resend.api_key
    @original_delivery_method = PasswordsMailer.delivery_method
    Resend.api_key = "test-only-key"
    PasswordsMailer.delivery_method = :resend
    @requests = []
  end

  teardown do
    Resend.api_key = @original_api_key
    PasswordsMailer.delivery_method = @original_delivery_method
  end

  test "rate limits respect retry after and use a bounded schedule" do
    travel_to Time.current.change(usec: 0) do
      with_http_responses({ statusCode: 429, message: "private-response", headers: { "retry-after" => "42" } }) do
        PasswordsMailer.deliver_reset_later(@user)
        ActiveJob::Base.execute(enqueued_jobs.shift)
        assert_equal 1, enqueued_jobs.size
        assert_in_delta 42, enqueued_jobs.first[:at] - Time.current.to_f, 0.01
      end
    end
  end

  test "all server statuses retry but permanent SDK errors do not" do
    [ 500, 502, 503, 599 ].each do |status|
      clear_enqueued_jobs
      with_http_responses({ statusCode: status, message: "private-response" }) do
        PasswordsMailer.deliver_reset_later(@user)
        ActiveJob::Base.execute(enqueued_jobs.shift)
        assert_equal 1, enqueued_jobs.size, "HTTP #{status} should retry"
      end
    end

    [ [ 400, "validation_error" ], [ 401, "missing_api_key" ], [ 403, "validation_error" ],
      [ 422, "validation_error" ], [ 409, "invalid_idempotent_request" ], [ 409, "concurrent_idempotent_requests" ] ].each do |status, name|
      clear_enqueued_jobs
      with_http_responses({ statusCode: status, name: name, message: "private-response" }) do
        PasswordsMailer.deliver_reset_later(@user)
        error = assert_raises(Resend::Error) { ActiveJob::Base.execute(enqueued_jobs.shift) }
        refute_includes error.full_message, "private-response"
        assert_empty enqueued_jobs, "HTTP #{status} should not retry"
      end
    end
  end

  test "timeouts and temporary connection failures retry" do
    [ Net::ReadTimeout, Net::OpenTimeout, Net::WriteTimeout, SocketError, EOFError,
      Errno::ECONNRESET, Errno::ECONNREFUSED, Errno::ETIMEDOUT ].each do |error_class|
      clear_enqueued_jobs
      with_http_responses(error_class.new("private-network-message")) do
        PasswordsMailer.deliver_reset_later(@user)
        ActiveJob::Base.execute(enqueued_jobs.shift)
        assert_equal 1, enqueued_jobs.size, "#{error_class} should retry"
      end
    end
  end

  test "four total attempts share a retry budget across different transient errors" do
    with_http_responses(
      { statusCode: 429, message: "private-response" },
      { statusCode: 503, message: "private-response" },
      Net::ReadTimeout.new,
      { statusCode: 500, message: "private-response" }
    ) do
      PasswordsMailer.deliver_reset_later(@user)
      3.times do |attempt|
        travel_to Time.current.change(usec: 0) do
          ActiveJob::Base.execute(enqueued_jobs.shift)
          delay = enqueued_jobs.first[:at] - Time.current.to_f
          base = 15 * 2**attempt
          assert_operator delay, :>=, base
          assert_operator delay, :<=, base * 1.15
          assert_operator delay, :<=, 120
        end
      end
      assert_raises(Resend::Error::InternalServerError) { ActiveJob::Base.execute(enqueued_jobs.shift) }
      assert_equal 4, @requests.size
      assert_empty enqueued_jobs
    end
  end

  test "retries reuse identical payload and key after an uncertain network outcome" do
    with_http_responses(Net::ReadTimeout.new, { id: "accepted-message" }) do
      PasswordsMailer.deliver_reset_later(@user)
      ActiveJob::Base.execute(enqueued_jobs.shift)
      retry_job = enqueued_jobs.shift
      travel_to Time.at(retry_job[:at]) do
        ActiveJob::Base.execute(retry_job)
      end
      assert_equal 2, @requests.size
      assert_equal @requests.first, @requests.last
      assert @requests.first.last[:headers]["Idempotency-Key"].present?
      assert_empty enqueued_jobs
    end
  end

  test "separate requests have distinct idempotency keys even at the same time" do
    travel_to Time.current do
      with_http_responses({ id: "first" }, { id: "second" }) do
        2.times { PasswordsMailer.deliver_reset_later(@user) }
        2.times { ActiveJob::Base.execute(enqueued_jobs.shift) }
        keys = @requests.map { |_url, options| options[:headers]["Idempotency-Key"] }
        assert_equal 2, keys.uniq.size
      end
    end
  end

  test "expired or invalidated tokens are not sent after queue delays" do
    with_http_responses do
      PasswordsMailer.deliver_reset_later(@user)
      travel 16.minutes do
        ActiveJob::Base.execute(enqueued_jobs.shift)
      end
      PasswordsMailer.deliver_reset_later(@user)
      @user.update!(password: "replacement-password")
      ActiveJob::Base.execute(enqueued_jobs.shift)
      assert_empty @requests
      assert_empty enqueued_jobs
    end
  end

  test "a token that expires while waiting for a retry is not sent" do
    with_http_responses(Net::ReadTimeout.new) do
      PasswordsMailer.deliver_reset_later(@user)
      ActiveJob::Base.execute(enqueued_jobs.shift)
      travel 16.minutes do
        ActiveJob::Base.execute(enqueued_jobs.shift)
      end
      assert_equal 1, @requests.size
      assert_empty enqueued_jobs
    end
  end

  test "a password change while waiting for a retry invalidates the queued email" do
    with_http_responses(Net::ReadTimeout.new) do
      PasswordsMailer.deliver_reset_later(@user)
      ActiveJob::Base.execute(enqueued_jobs.shift)
      @user.update!(password: "replacement-password")
      ActiveJob::Base.execute(enqueued_jobs.shift)
      assert_equal 1, @requests.size
      assert_empty enqueued_jobs
    end
  end

  test "retry delays do not outlive the token safety margin" do
    with_http_responses({ statusCode: 429, message: "private-response", headers: { "retry-after" => "120" } }) do
      PasswordsMailer.deliver_reset_later(@user)
      travel 13.minutes do
        ActiveJob::Base.execute(enqueued_jobs.shift)
      end
      assert_equal 1, @requests.size
      assert_empty enqueued_jobs
    end
  end

  test "impractical retry after values surface instead of retrying too early" do
    with_http_responses({ statusCode: 429, message: "private-response", headers: { "retry-after" => "3600" } }) do
      PasswordsMailer.deliver_reset_later(@user)
      error = assert_raises(Resend::Error::RateLimitExceededError) { ActiveJob::Base.execute(enqueued_jobs.shift) }
      assert_equal 3600, error.retry_after
      assert_empty enqueued_jobs
    end
  end

  test "queued token and mail content are omitted from job logs" do
    output = StringIO.new
    original_logger = PasswordResetDeliveryJob.logger
    PasswordResetDeliveryJob.logger = ActiveSupport::Logger.new(output)
    PasswordsMailer.deliver_reset_later(@user)
    token = enqueued_jobs.first[:args].first
    refute_includes output.string, token
    refute_includes output.string, @user.email_address
    assert_includes output.string, "PasswordResetDeliveryJob"
  ensure
    PasswordResetDeliveryJob.logger = original_logger
  end

  private
    def with_http_responses(*responses)
      original = HTTParty.method(:post)
      requests = @requests
      HTTParty.define_singleton_method(:post) do |url, options|
        requests << [ url, options ]
        data = responses.shift || raise("Unexpected HTTP request")
        raise data if data.is_a?(Exception)
        headers = data.fetch(:headers, {})
        body = data.except(:headers).transform_keys(&:to_s)
        Struct.new(:body, :parsed_response, :headers).new(JSON.generate(body), body, headers)
      end
      yield
    ensure
      HTTParty.define_singleton_method(:post, original)
    end
end
