require 'test_helper'

class EmailMailerTest < ActionMailer::TestCase
  test "cron" do
    mail = EmailMailer.cron
    assert_equal "Cron", mail.subject
    assert_equal ["to@example.org"], mail.to
    assert_equal ["from@example.com"], mail.from
    assert_match "Hi", mail.body.encoded
  end

end
