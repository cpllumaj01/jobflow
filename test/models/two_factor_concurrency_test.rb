require "test_helper"

class TwoFactorConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @user = User.create!(email_address: "concurrent-2fa@example.com", password: "concurrency-test-password")
    secret = ROTP::Base32.random
    @codes = @user.enable_two_factor!(secret: secret, code: ROTP::TOTP.new(secret).now)
  end

  teardown { @user&.destroy! }

  test "concurrent recovery code redemption succeeds exactly once" do
    ready = Queue.new
    start = Queue.new
    threads = Array.new(2) do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          user = User.find(@user.id)
          ready << true
          start.pop
          user.consume_two_factor!(@codes.first)
        end
      end
    end
    2.times { ready.pop }
    2.times { start << true }
    results = threads.map(&:value)
    assert_equal 1, results.count(true)
    assert_equal 1, results.count(false)
    assert_equal 9, @user.reload.recovery_code_digests.size
  ensure
    threads&.each(&:join)
  end
end
