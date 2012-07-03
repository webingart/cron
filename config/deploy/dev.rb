set :application, "#{application_base_name}_#{stage}"
set :domain, "#{stage}.#{domain}"
set :deploy_to, "/var/www/#{application}"