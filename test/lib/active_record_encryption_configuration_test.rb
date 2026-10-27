require "test_helper"
require "open3"

class ActiveRecordEncryptionConfigurationTest < ActiveSupport::TestCase
  test "production requires each encryption variable without exposing values" do
    environment = {
      "RAILS_ENV" => "production", "APP_HOST" => "jobflow.example.org", "MAILER_FROM" => "reset@example.org",
      "RESEND_API_KEY" => "test-only-key", "SECRET_KEY_BASE" => SecureRandom.hex(64), "SECRET_KEY_BASE_DUMMY" => nil
    }
    keys = %w[PRIMARY_KEY DETERMINISTIC_KEY KEY_DERIVATION_SALT].to_h do |setting|
      [ "ACTIVE_RECORD_ENCRYPTION_#{setting}", SecureRandom.hex(32) ]
    end
    keys.each_key do |missing|
      output, error, status = Open3.capture3(environment.merge(keys).merge(missing => ""), "bin/rails", "runner", "nil")
      assert_not status.success?
      assert_includes error, "#{missing} is required for Active Record Encryption"
      keys.each_value { |value| refute_includes output + error, value }
    end
  end

  test "parameter and model inspection filtering includes all second factor credentials" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    values = {
      "password" => "private-password", "verification_code" => "123456", "otp_secret" => "private-secret",
      "recovery_codes" => [ "private-code" ], "recovery_code_digests" => [ "private-digest" ],
      "two_factor_login_token" => "private-token", "name" => "Kitchen code review", "status" => "new"
    }
    filtered = filter.filter(values)
    values.except("name", "status").each_key { |key| assert_equal "[FILTERED]", filtered[key] }
    assert_equal values["name"], filtered["name"]
    assert_equal "new", filtered["status"]
    user = users(:one)
    user.recovery_code_digests = [ "private-digest" ]
    refute_includes user.inspect, "private-digest"
  end
end
