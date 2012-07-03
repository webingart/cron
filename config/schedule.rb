set :job_template, "bash -l -c 'rvm 1.9.3 && :job'"
job_type :rake, "cd :path && RAILS_ENV=:environment bundle exec rake :task :output"
job_type :runner, "cd :path && rails runner -e :environment ':task' :output"

every 1.minute do
  rake "email:cron"
end