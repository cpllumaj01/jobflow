require "application_system_test_case"

class JobAttachmentsTest < ApplicationSystemTestCase
  setup do
    @job = jobs(:kitchen_renovation)
    @job.files.attach(io: StringIO.new("Existing scope"), filename: "existing.txt", content_type: "text/plain")
    visit new_session_path
    fill_in "Email address", with: users(:one).email_address
    fill_in "Password", with: "password"
    click_on "Sign in"
    assert_button "Log out"
  end

  teardown do
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    page.driver.browser.execute_cdp("Emulation.setTouchEmulationEnabled", enabled: false)
    page.driver.browser.execute_cdp("Emulation.setScriptExecutionDisabled", value: false)
    @temporary_files&.each(&:close!)
  end

  [ 320, 1400 ].each do |width|
    test "invalid selections are blocked and can be corrected at #{width}px" do
      page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
        width: width, height: 1000, deviceScaleFactor: 1, mobile: width == 320)
      page.driver.browser.execute_cdp("Emulation.setTouchEmulationEnabled", enabled: width == 320)
      visit job_path(@job)
      oversized = temporary_file("oversized", ".txt")
      oversized.truncate(Job::MAX_FILE_SIZE + 1)
      unsupported = temporary_file("unsupported-#{'long' * 40}", ".exe")
      unsupported.write("program")
      unsupported.flush
      empty = temporary_file("empty", ".txt")

      attach_file "Choose files", [ file_fixture("project.txt"), oversized.path, unsupported.path, empty.path ]
      assert_selector "#file-upload-errors li", count: 3
      assert_selector "#file-upload-errors", text: "#{File.basename(oversized.path)}: must be 20 MB or smaller"
      assert_selector "#file-upload-errors", text: "#{File.basename(unsupported.path)}: unsupported format"
      assert_selector "#file-upload-errors", text: "#{File.basename(empty.path)}: is empty"
      assert_selector "input[type=file][aria-invalid=true]"
      assert find_field("Choose files").evaluate_script("this.validity.customError")
      assert_fits(width)

      assert_no_difference([ "ActiveStorage::Blob.count", "ActiveStorage::Attachment.count", "Activity.count" ]) do
        click_on "Upload files"
        assert_current_path job_path(@job)
        assert_selector "#file-upload-errors li", count: 3
      end
      assert_equal [ "existing.txt" ], @job.reload.files.map { |file| file.filename.to_s }

      # Clearing a rejected selection removes custom errors; native required validation remains.
      find_field("Choose files").native.clear
      assert_no_selector "#file-upload-errors li"
      assert_selector "input[type=file][aria-invalid=false]"
      assert find_field("Choose files").evaluate_script("this.validity.valueMissing")

      at_limit = temporary_file("at-limit", ".txt")
      at_limit.write("a" * Job::MAX_FILE_SIZE)
      at_limit.flush
      attach_file "Choose files", [ at_limit.path, file_fixture("photo.png") ]
      assert_no_selector "#file-upload-errors li"
      assert find_field("Choose files").evaluate_script("this.validity.valid")
      assert_fits(width)
      click_on "Upload files"
      assert_text "Files were successfully uploaded."
      assert_current_path job_path(@job)
      assert_link "existing.txt"
      assert_link File.basename(at_limit.path)
      assert_link "photo.png"
      assert_equal 3, @job.reload.files.count
      assert_equal 2, @job.activities.where(event: "attachment_added").count
      assert_fits(width)
    end
  end

  test "submission rechecks files even when selection did not emit a change event" do
    visit job_path(@job)
    page.execute_script(<<~JS)
      const input = document.getElementById("job_files")
      const selection = new DataTransfer()
      selection.items.add(new File(["program"], "program.exe"))
      input.files = selection.files
      input.form.requestSubmit()
    JS
    assert_current_path job_path(@job)
    assert_selector "#file-upload-errors", text: "program.exe: unsupported format"
    assert_selector "input[type=file][aria-invalid=true]"
    assert_equal 1, @job.reload.files.count
    assert_equal 0, @job.activities.count
  end

  test "server rejection remains usable on mobile without JavaScript" do
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
      width: 320, height: 1000, deviceScaleFactor: 1, mobile: true)
    page.driver.browser.execute_cdp("Emulation.setTouchEmulationEnabled", enabled: true)
    page.driver.browser.execute_cdp("Emulation.setScriptExecutionDisabled", value: true)
    visit job_path(@job)
    unsupported = temporary_file("unsupported-#{'long' * 40}", ".exe")
    unsupported.write("program")
    unsupported.flush
    attach_file "Choose files", [ file_fixture("project.txt"), unsupported.path ]
    click_on "Upload files"
    assert_selector "[role=alert]", text: "has an unsupported format"
    assert_link "existing.txt"
    assert_equal 1, @job.reload.files.count
    assert_equal 0, @job.activities.count

    page.driver.browser.execute_cdp("Emulation.setScriptExecutionDisabled", value: false)
    assert_fits(320)
  end

  private
    def temporary_file(name, extension)
      file = Tempfile.new([ name, extension ])
      (@temporary_files ||= []) << file
      file
    end

    def assert_fits(width)
      assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, width
      within "section[aria-labelledby='attachments-heading']" do
        all("input[type=file], input[type=submit]").each do |control|
          rect = control.evaluate_script("this.getBoundingClientRect().toJSON()")
          assert_operator rect["left"], :>=, 0
          assert_operator rect["right"], :<=, width
          assert_operator rect["height"], :>=, 44
        end
      end
    end
end
