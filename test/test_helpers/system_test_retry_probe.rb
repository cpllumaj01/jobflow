# Executed in a subprocess by SystemTestRetryTest to exercise real Minitest exits.
require "application_system_test_case"

base = case ENV.fetch("RETRY_PROBE_KIND")
when "system" then ApplicationSystemTestCase
when "unit" then ActiveSupport::TestCase
when "integration" then ActionDispatch::IntegrationTest
end

class SystemTestRetryProbe < base
  driven_by :rack_test if superclass == ApplicationSystemTestCase && ENV["RETRY_PROBE_BROWSER"] != "true"

  setup do
    @probe_attempt = (@probe_attempt || 0) + 1
    puts "PROBE setup #{@probe_attempt}"
    assert_equal "Kitchen Renovation", jobs(:kitchen_renovation).reload.name
    jobs(:kitchen_renovation).update!(name: "Changed during attempt")
  end

  teardown do
    puts "PROBE teardown #{@probe_attempt}"
  end

  test "retry probe" do
    if is_a?(ApplicationSystemTestCase)
      visit new_session_path
      if ENV["RETRY_PROBE_BROWSER"] == "true"
        refute_includes page.evaluate_script("document.cookie"), "retry_probe=dirty"
        page.execute_script("document.cookie = 'retry_probe=dirty; path=/'")
      else
        assert_nil page.driver.browser.last_request.cookies["retry_probe"]
        page.driver.browser.set_cookie("retry_probe=dirty; path=/")
      end
      puts "PROBE screenshot path #{Capybara.save_path}"
    end
    puts "PROBE attempt #{@probe_attempt}"
    raise "original error attempt #{@probe_attempt}" if ENV["RETRY_PROBE_ERROR"] == "true" && @probe_attempt < 3
    assert @probe_attempt >= ENV.fetch("RETRY_PROBE_PASS_ON").to_i, "original failure attempt #{@probe_attempt}"
  end

  test "already passing" do
    puts "PROBE already passing"
    assert true
  end

  test "skipped" do
    puts "PROBE skipped"
    skip "intentional probe skip"
  end
end
