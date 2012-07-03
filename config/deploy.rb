require "deprec"
require "bundler/capistrano"

# rvm tu mame, protoze nase serverova konfigurace umoznuje pouziti ruznych verzi Ruby soucasne
$:.unshift(File.expand_path('./lib', ENV['rvm_path']))
require "rvm/capistrano"
set :rvm_ruby_string, "1.9.3"

# nastaveni a zavadeni podpory pro 'stages', tj. production, dev, pripadne dalsi, stage dev mame jako vychozi
set :stages, %w(dev production) # zde mozno dle potreby pridat dalsi stages
set :dafault_stage, "dev"
require "capistrano/ext/multistage"

set :whenever_command, "bundle exec whenever"
require 'whenever/capistrano'

# --- tady zacina volitelna konfigurace ----------------------------------------

# DULEZITE 1:
# Pro aplikace, ktere nemaji SSL certifikat bude zrejme potreba jeste odmazat cast konfiguraku pro Nginx.
# Jde o generator task engined:create_nginx_vhost_config, jsou tam patrne 3 sekce:
#   upstream, server pro port 80 (klasika) a server pro port 443 (SSL)
# .. tak to zahodit. ;)

# DULEZITE 2:
# Soucasti deploy.rb je take slozka config/deploy

# zakladni nazev aplikace, u production je konecny, u dev stage se pridava suffix _dev
set :application_base_name, "cron"

# definuje cilovy server a jeho role
server "37.59.183.209", :web, :app#,  :db nemame, protoze u mongodb to nema smysl

# Zde se nastavuje pocet procesu Rails aplikacniho serveru. S cisly opatrne, kazdy proces zere vlastni pamet.
# Minimalni pocet procesu, casto staci jeden, ale vzdy je dobry jeden v zaloze (nikoliv nutny)
set :passenger_min_instances, 2 # POZOR! Minimum je 1, 0 nefunguje!
# Maximalni pocet procesu, casto staci i 2, 4 jsou pro ty virtualy uz celkem rozumny strop, protoze VPS ma jen 2 CPU.
# Pokud se zda malo vykonu, mozno zvysit treba az na 6 nebo 8, ale to je potreba zkusit a subjektivne posoudit.
# Kazdy proces zere dost pameti, takze s citem.
set :passenger_max_instances, 4

# tady je par falesnych nastaveni, kterou jsou pak prepsane ve specifickych nastavenich pro dany stage,
# avsak zde byt, jinak by se deploy interaktivne dotazoval na tato nastaveni
set :application, application_base_name
set :domain, "cron.webingart.cz" # hlavni domena (bez www, zbytek se sestavi sam, mozno menit v config/deploy slozce)
set :custom_domains, "cron.webingart.cz"

# toto je definice vlastnich sdilenych adresaru, tj. tech, ktere pri deploy zustavaji bez zmeny, napr. zde mame 'uploads'
set :shared_dirs, %w()

set :scm, :git
set :copy_exclude, ['.git', 'doc', '.rvmrc', 'features', 'spec', 'test']
# Tady se nastavuje GIT repozitar a dalsi radek pak vetev v GIT.
# POZOR! Aktualne je to autodetekce vetve, ve ktere se nachazim!
# Pokud chci natvrdo specifickou vetev, napr. master, pak tam bude:
# set :branche, "master"
set :repository,  "git@github.com:webingart/cron.git"
set :branche, `git branch | grep '*' | awk '{ print $2 }'`.split[0]

# --- tady konci volitelna konfigurace, zbytek neni obvykle treba menit --------

set :shared_children, shared_children + shared_dirs

set :ruby_vm_type, :mri
set :web_server_type, :nginx
set :app_server_type, :passenger

set :deploy_to, "/var/www/#{application}"
set :deploy_env, defer { stage }
set :user, "deploy"

set :deploy_via, :remote_cache
set :checkout, "export"
set :rake, lambda { "#{fetch(:bundle_cmd, "bundle")} exec rake" }

set :monit_conf_dir, "/etc/monit/conf.d"
set :nginx_vhost_dir, "/etc/nginx/sites-available"
set :nginx_vhost_dir_enabled, "/etc/nginx/sites-enabled"

default_run_options[:pty] = true

# ------------------------------------------------------------------------------

namespace :deploy do

  task :start do ; end
  task :stop do ; end

  task :restart, :roles => :app, :except => { :no_release => true } do
    run "#{try_sudo} touch #{File.join(current_path, 'tmp', 'restart.txt')}"
  end

  task :setup, :except => { :no_release => true }, :roles => [:app, :web] do
    dirs = [deploy_to, releases_path, shared_path]
    dirs += shared_children.map { |d| File.join(shared_path, d) }
    run "#{try_sudo} mkdir -p #{dirs.join(' ')} && #{try_sudo} chmod g+w #{dirs.join(' ')}"
  end

  task :start, :roles => :app, :except => { :no_release => true } do
    run "#{try_sudo} /etc/init.d/passenger-#{application} start"
  end

  task :stop, :roles => :app, :except => { :no_release => true } do
    run "#{try_sudo} /etc/init.d/passenger-#{application} stop"
  end

end

namespace :deprec do

  # --- NGINX ------------------------------------------------------------------
  namespace :nginx do
    SYSTEM_CONFIG_FILES[:nginx] = []
    PROJECT_CONFIG_FILES[:nginx] = []

    task :config_gen_project, :roles => :web do
      run "mkdir -p #{deploy_to}/passenger"
      engined.create_nginx_vhost_config
      engined.create_nginx_logrotate_config
    end

    task :config_project, :roles => :web do
      symlink_nginx_vhost
      symlink_nginx_logrotate
    end

    task :symlink_nginx_vhost, :roles => :web do
      sudo "ln -sf #{deploy_to}/passenger/nginx_vhost.conf #{nginx_vhost_dir}/#{application}"
    end

    task :symlink_nginx_logrotate, :roles => :web do
      sudo "ln -sf #{deploy_to}/passenger/nginx_logrotate.conf /etc/logrotate.d/nginx-#{application}"
    end
  end

  # --- PASSENGER --------------------------------------------------------------
  namespace :passenger do
    SYSTEM_CONFIG_FILES[:passenger] = []
    PROJECT_CONFIG_FILES[:passenger] = []

    task :config_gen_project do
      run "mkdir -p #{deploy_to}/passenger"
      engined.create_passenger_init_script
      engined.create_passenger_logrotate_conf
    end

    task :config_project, :roles => :app do
      deprec2.push_configs(:passenger, PROJECT_CONFIG_FILES[:passenger])
      symlink_logrotate_config
      symlink_nginx_vhost
      symlink_passenger_init_script
      activate_project
    end

    task :symlink_passenger_init_script, :roles => :app do
      sudo "ln -sf #{deploy_to}/passenger/passengerctl /etc/init.d/passenger-#{application}"
    end

    task :symlink_nginx_vhost, :roles => :app do
      sudo "ln -sf #{deploy_to}/passenger/nginx_vhost.conf #{nginx_vhost_dir}/#{application}"
    end

    task :activate_system, :roles => :app do
      top.deprec.web.reload
    end

    task :activate_project, :roles => :app do
      activate_passenger
      sudo "ln -sf #{nginx_vhost_dir}/#{application} #{nginx_vhost_dir_enabled}/#{application}"
      top.deprec.web.reload
    end

    task :activate_passenger, :roles => :app do
      sudo "update-rc.d passenger-#{application} defaults"
    end
  end
end

# --- generators ---------------------------------------------------------------

#namespace :dragonfly do
#  task :symlink do
#    run "ln -s #{shared_path}/public/images #{release_path}/public"
#  end
#end
#
#after 'deploy:update_code', 'dragonfly:symlink'

namespace :engined do

  # --- NGINX ------------------------------------------------------------------

  task :create_nginx_vhost_config, :roles => :web do
    nginx_vhost_config = ERB.new <<-EOF
upstream #{application} {
  server unix:#{shared_path}/pids/passenger.sock;
}
server {
  listen 80;
  server_name #{domain} #{custom_domains};

  access_log #{shared_path}/log/#{domain}-access.log;
  error_log #{shared_path}/log/#{domain}-error.log notice;

  root #{current_path}/public;
  
  if ($host ~* ^cron.webingart.cz$) {
    rewrite ^(.*) http://www.cron.webingart.cz$1 permanent;
  }

  location / {
    proxy_pass http://#{application};
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
  }

  if (\$request_filename ~* .(css|jpg|gif|png)$) {
    break;
  }

  if (-f \$document_root/system/maintenance.html) {
    return 503;
  }

  # set Expire header on assets: see http://developer.yahoo.com/performance/rules.html#expires
  location ~ ^/(images|javascripts|stylesheets)/ {
    expires max;
    error_page 404 = @fallback;
  }

  location @fallback {
    proxy_pass http://#{application};
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
  }
  client_max_body_size 100M;
  error_page 404 /404.html;
  error_page 500 504 /500.html;
  error_page 502 @503;
  error_page 503 @503;
  location @503 {
    rewrite ^(.*)\$ /system/maintenance.html break;
  }
}
EOF
    put nginx_vhost_config.result, "#{deploy_to}/passenger/nginx_vhost.conf"
  end

  task :create_nginx_logrotate_config, :roles => :web do
    nginx_logrotate_config = ERB.new <<-EOF
#{shared_path}/log/*access.log #{shared_path}/log/*error.log {
  daily
  missingok
  rotate 30
  compress
  delaycompress
  sharedscripts
  dateext
  postrotate
    service nginx reload
  endscript
}
EOF
    put nginx_logrotate_config.result, "#{deploy_to}/passenger/nginx_logrotate.conf"
  end

  # --- PASSENGER --------------------------------------------------------------

  task :create_passenger_init_script, :roles => :app do
    passenger_init_script = ERB.new <<-EOF
#!/bin/bash

APPLICATION=#{application}
RVM_RUBY=#{rvm_ruby_string}
ENVIRONMENT=#{deploy_env}
INSTANCES_MIN=#{passenger_min_instances}
INSTANCES_MAX=#{passenger_max_instances}

source /usr/local/lib/passengerctl
EOF
    put passenger_init_script.result, "#{deploy_to}/passenger/passengerctl"
    run "chmod 755 #{deploy_to}/passenger/passengerctl"
  end

  task :create_passenger_logrotate_conf, :roles => :app do
    passenger_logrotate_conf = ERB.new <<-EOF
#{shared_path}/log/#{deploy_env}.log {
  daily
  missingok
  rotate 30
  compress
  delaycompress
  sharedscripts
  dateext
  postrotate
    touch #{current_path}/tmp/restart.txt
  endscript
}
EOF
    put passenger_logrotate_conf.result, "#{deploy_to}/passenger/logrotate.conf"
  end

end