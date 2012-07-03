class MailsController < ApplicationController
  def index
    EmailMailer.cron.deliver
  end
end
