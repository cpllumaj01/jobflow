require "test_helper"

class PasswordsMailerTest < ActionMailer::TestCase
  test "reset identifies JobFlow and links to a valid expiring token" do
    user = users(:one)
    mail = PasswordsMailer.reset(user)

    assert_equal [ user.email_address ], mail.to
    assert_equal [ "from@example.com" ], mail.from
    assert_equal "Reset your JobFlow password", mail.subject
    [ mail.html_part, mail.text_part ].each do |part|
      body = part.body.decoded
      assert_includes body, "JobFlow"
      assert_includes body, "15 minutes"
      assert_includes body, "If you did not request this"
      token = body.match(%r{http://example.com/passwords/([^/]+?)/edit})[1]
      assert_equal user, User.find_by_password_reset_token!(token)
    end
  end
end
