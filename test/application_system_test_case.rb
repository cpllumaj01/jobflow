require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  browser = ENV.fetch("TEST_HEADLESS", "true") == "true" ? :headless_chrome : :chrome
  driven_by :selenium, using: browser, screen_size: [ 1400, 1000 ]
end
