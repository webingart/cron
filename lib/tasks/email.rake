namespace :email do 
  
  desc "Merge archive and live db"
  task :cron => :environment do
    EmailMailer.cron.deliver
  end

end