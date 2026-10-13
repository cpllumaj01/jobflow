require "test_helper"
require "open3"

class ProductionEmailConfigurationTest < ActiveSupport::TestCase
  test "production uses Resend with an explicit HTTPS host and sender" do
    script = <<~'SCRIPT'
      user = Struct.new(:email_address, :password_reset_token, :password_reset_token_expires_in).new("recipient@example.org", "test-token", 15.minutes)
      mail = PasswordsMailer.reset(user)
      puts JSON.generate({
        method: ActionMailer::Base.delivery_method,
        urls: ActionMailer::Base.default_url_options,
        sender: mail[:from].decoded,
        body: mail.text_part.body.decoded,
        errors: ActionMailer::Base.raise_delivery_errors,
        deliveries: ActionMailer::Base.perform_deliveries
      })
    SCRIPT
    output, error, status = Open3.capture3(
      { "RAILS_ENV" => "production", "APP_HOST" => "jobflow.example.org", "MAILER_FROM" => "JobFlow <reset@example.org>",
        "RESEND_API_KEY" => "test-only-key", "SECRET_KEY_BASE" => "test-secret-" * 8, "SECRET_KEY_BASE_DUMMY" => nil, "RESEND_BASE_URL" => nil },
      "bin/rails", "runner", script
    )
    assert status.success?, error
    config = JSON.parse(output.lines.last)
    assert_equal "resend", config["method"]
    assert_equal({ "host" => "jobflow.example.org", "protocol" => "https" }, config["urls"])
    assert_equal "JobFlow <reset@example.org>", config["sender"]
    assert_includes config["body"], "https://jobflow.example.org/passwords/test-token/edit"
    assert config["errors"]
    assert config["deliveries"]
    assert_equal :test, ActionMailer::Base.delivery_method
  end

  test "production rejects missing email settings and non-host URL values" do
    environment = {
      "RAILS_ENV" => "production", "APP_HOST" => "jobflow.example.org",
      "MAILER_FROM" => "JobFlow <reset@example.org>", "RESEND_API_KEY" => "test-only-key",
      "SECRET_KEY_BASE" => "test-secret-" * 8, "SECRET_KEY_BASE_DUMMY" => nil, "RESEND_BASE_URL" => nil
    }
    %w[APP_HOST MAILER_FROM RESEND_API_KEY].each do |name|
      _output, error, status = Open3.capture3(environment.merge(name => ""), "bin/rails", "runner", "nil")
      refute status.success?
      assert_includes error, "#{name} is required in production"
    end
    _output, error, status = Open3.capture3(environment.merge("APP_HOST" => "https://jobflow.example.org/reset"), "bin/rails", "runner", "nil")
    refute status.success?
    assert_includes error, "APP_HOST must be a hostname"

    _output, error, status = Open3.capture3(environment.merge("RESEND_BASE_URL" => "http://api.resend.com/"), "bin/rails", "runner", "nil")
    refute status.success?
    assert_includes error, "RESEND_BASE_URL must use the official HTTPS endpoint"

    build_environment = environment.merge("APP_HOST" => nil, "MAILER_FROM" => nil, "RESEND_API_KEY" => nil, "SECRET_KEY_BASE_DUMMY" => "1")
    _output, error, status = Open3.capture3(build_environment, "bin/rails", "runner", "nil")
    assert status.success?, error
  end

  test "production log formatter removes reset tokens from paths and redirects" do
    formatter = PasswordResetLogFormatter.new
    message = 'Started GET "/passwords/private-token/edit" Redirected to https://example.org/passwords/another-token/edit'
    output = formatter.call("INFO", Time.current, nil, message)
    refute_includes output, "private-token"
    refute_includes output, "another-token"
    assert_includes output, "/passwords/[FILTERED]/edit"
  end
end
