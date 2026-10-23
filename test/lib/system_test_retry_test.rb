require "test_helper"
require "open3"

class SystemTestRetryTest < ActiveSupport::TestCase
  # Subprocesses use this worker's database and manage their own fixtures.
  self.fixture_table_names = []
  self.use_transactional_tests = false

  test "CI retries only failed system tests and reports recovery on the third attempt" do
    output, status = run_probe(ci: "true", pass_on: 3)

    assert status.success?, output
    assert_equal 3, output.scan(/PROBE attempt /).size
    assert_equal 5, output.scan(/PROBE setup /).size
    assert_equal 5, output.scan(/PROBE teardown /).size
    assert_equal 1, output.scan(/PROBE already passing/).size
    assert_equal 1, output.scan(/PROBE skipped/).size
    assert_includes output, "failed attempt 1/3:"
    assert_includes output, "original failure attempt 1"
    assert_includes output, "original failure attempt 2"
    assert_includes output, "system_test_retry_probe.rb:"
    assert_includes output, "attempt 2/3"
    assert_includes output, "attempt 3/3"
    assert_includes output, "passed only after retrying (attempt 3/3)"

    paths = output.lines.grep(/PROBE screenshot path/).map(&:strip)
    assert_equal 3, paths.uniq.size
    (1..3).each { |attempt| assert paths.any? { |path| path.end_with?("/attempt-#{attempt}") } }
  end

  test "CI retries errors as well as assertions and stops after a successful retry" do
    output, status = run_probe(ci: "true", pass_on: 1, error: true)

    assert status.success?, output
    assert_equal 3, output.scan(/PROBE attempt /).size
    assert_includes output, "original error attempt 1"
    assert_includes output, "RuntimeError"
    assert_includes output, "passed only after retrying"

    output, status = run_probe(ci: "true", pass_on: 2)
    assert status.success?, output
    assert_equal 2, output.scan(/PROBE attempt /).size
    assert_includes output, "passed only after retrying (attempt 2/3)"
  end

  test "persistent system test failures exit unsuccessfully after three total attempts" do
    output, status = run_probe(ci: "true", pass_on: 4)

    refute status.success?, output
    assert_equal 3, output.scan(/PROBE attempt /).size
    (1..3).each { |attempt| assert_includes output, "original failure attempt #{attempt}" }
    refute_includes output, "passed only after retrying"
    refute_includes output, "attempt 4/3"
  end

  test "unit and integration tests never retry even when the system helper is loaded in CI" do
    %w[unit integration].each do |kind|
      output, status = run_probe(ci: "true", pass_on: 3, kind: kind)

      refute status.success?, output
      assert_equal 1, output.scan(/PROBE attempt /).size, output
      refute_includes output, "[SystemTestRetry]"
    end
  end

  test "local system tests run once and retain the default screenshot path" do
    output, status = run_probe(ci: nil, pass_on: 3)

    refute status.success?, output
    assert_equal 1, output.scan(/PROBE attempt /).size
    refute_includes output, "[SystemTestRetry]"
    refute_match(/PROBE screenshot path .*attempt-/, output)
  end

  private
    def run_probe(ci:, pass_on:, kind: "system", error: false)
      database_url = URI.parse(ENV.fetch("DATABASE_URL", "postgresql:///jobflow_test"))
      database_url.path = "/#{ActiveRecord::Base.connection_db_config.database}"
      Open3.capture2e(
        { "CI" => ci, "PARALLEL_WORKERS" => "1", "RETRY_PROBE_KIND" => kind,
          "RETRY_PROBE_PASS_ON" => pass_on.to_s, "RETRY_PROBE_ERROR" => error.to_s,
          "DATABASE_URL" => database_url.to_s },
        "bundle", "exec", "ruby", "-Itest", "test/test_helpers/system_test_retry_probe.rb"
      )
    end
end
