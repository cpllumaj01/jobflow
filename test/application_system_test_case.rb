require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  browser = ENV.fetch("TEST_HEADLESS", "true") == "true" ? :headless_chrome : :chrome
  driven_by :selenium, using: browser, screen_size: [ 1400, 1000 ]

  if ENV["CI"].present?
    require "minitest/retry"

    Minitest::Retry.use!(retry_count: 2, classes_to_retry: [ "ApplicationSystemTestCase" ], verbose: false)
    Minitest::Retry.on_retry do |klass, name, retry_count, result|
      puts "\n[SystemTestRetry] #{klass}##{name} failed attempt #{retry_count}/3:\n#{result}"
      puts "[SystemTestRetry] Retrying #{klass}##{name}, attempt #{retry_count + 1}/3"
    end

    def run
      original_save_path = Capybara.save_path
      result = super
      if result.passed? && @retry_attempt > 1
        puts "[SystemTestRetry] #{self.class}##{name} passed only after retrying (attempt #{@retry_attempt}/3)"
      end
      result
    ensure
      Capybara.save_path = original_save_path
    end

    def before_setup
      @retry_attempt = (@retry_attempt || 0) + 1
      # Rails reuses failure screenshot names, so retain each attempt separately.
      Capybara.save_path = Rails.root.join("tmp/screenshots", Process.pid.to_s, self.class.name, "attempt-#{@retry_attempt}")
      super
    end
  end
end
