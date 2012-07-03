class EmailMailer < ActionMailer::Base
  default from: "from@example.com"
  def cron
    mail to: "witek@webingart.cz"
  end
end
