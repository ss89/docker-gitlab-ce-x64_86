FROM ubuntu:16.10
MAINTAINER docker@x2d2.de
EXPOSE 80

#Update package sources
RUN apt update

#Install all the deps
RUN apt-get install -y nodejs ruby libcurl4-openssl-dev libexpat1-dev gettext libz-dev libssl-dev build-essential zlib1g-dev libyaml-dev libssl-dev libgdbm-dev libreadline-dev libncurses5-dev libffi-dev curl openssh-server checkinstall libxml2-dev libxslt-dev libcurl4-openssl-dev libicu-dev logrotate python-docutils pkg-config cmake ruby git logrotate libxml2 cmake pkg-config openssl libicu57 python2.7 python-setuptools curl golang postgresql sudo redis-server ruby-dev libicu-dev libpq-dev ruby-execjs nginx

#Add git user and create folders/chmod them
RUN useradd git && mkdir -p /home/git/repositories && chown -R git:git /home/git

#Install yarn
RUN cd /home/git && sudo -u git -g git -H touch /home/git/.bashrc && sudo -u git -g git -H curl --location https://yarnpkg.com/install.sh | sudo -u git -g git -H bash -

#Create DB User and give it permissions
RUN service postgresql start && sudo -u postgres -i psql -d postgres -c "CREATE USER git;" && sudo -u postgres -i psql -d postgres -c "CREATE DATABASE  gitlabhq_production OWNER git;" && sudo -u postgres -i psql -d postgres -c "GRANT ALL PRIVILEGES ON  DATABASE gitlabhq_production to git;" && sudo -u postgres -i psql -d postgres -c "ALTER USER git CREATEDB;" && sudo -u postgres -i psql -d postgres -c "ALTER DATABASE gitlabhq_production owner to git;" && sudo -u postgres -i psql -d postgres -c "ALTER USER git WITH SUPERUSER;"

#Configure redis
RUN cp /etc/redis/redis.conf /etc/redis/redis.conf.bak && sed 's/^port .*/port 0/' /etc/redis/redis.conf.bak | sed 's/# unixsocket/unixsocket/' | sed 's/unixsocketperm 700/unixsocketperm 777/' | tee /etc/redis/redis.conf

#Clone gitlab
RUN cd /home/git && sudo -u git -H git clone https://gitlab.com/gitlab-org/gitlab-ce.git -b 9-0-stable gitlab

#Configure gitlab
RUN sudo -u git -H cp /home/git/gitlab/config/gitlab.yml.example /home/git/gitlab/config/gitlab.yml && sudo -u git -H cat /home/git/gitlab/config/gitlab.yml.example | sed 's/port: 80 /port: 8080 /' | tee /home/git/gitlab/config/gitlab.yml && sudo -u git -H cp /home/git/gitlab/config/secrets.yml.example /home/git/gitlab/config/secrets.yml && sudo -u git -H cp /home/git/gitlab/config/unicorn.rb.example /home/git/gitlab/config/unicorn.rb && sudo -u git -H cp /home/git/gitlab/config/initializers/rack_attack.rb.example /home/git/gitlab/config/initializers/rack_attack.rb && sudo -u git -H cat /home/git/gitlab/config/resque.yml.example > /home/git/gitlab/config/resque.yml && sudo -u git -H cat /home/git/gitlab/config/database.yml.postgresql | head -n 8 | sed 's/pool: 10/pool: 10\n  template: template0/' | sudo -u git -H tee /home/git/gitlab/config/database.yml && chmod o-rwx /home/git/gitlab/config/database.yml

#Configure secrets, chown gitlab folders
RUN sudo -u git -H chmod 0600 /home/git/gitlab/config/secrets.yml && sudo chown -R git /home/git/gitlab/log/ && sudo chown -R git /home/git/gitlab/tmp/ && sudo chmod -R u+rwX,go-w /home/git/gitlab/log/ && sudo chmod -R u+rwX /home/git/gitlab/tmp/ && sudo chmod -R u+rwX /home/git/gitlab/tmp/pids/ && sudo chmod -R u+rwX /home/git/gitlab/tmp/sockets/ && mkdir /home/git/gitlab/public/uploads && chown -R git:git /home/git && sudo chmod 0700 /home/git/gitlab/public/uploads && sudo chmod -R u+rwX /home/git/gitlab/builds/

#Configure git
RUN sudo -u git -H git config --global core.autocrlf input && sudo -u git -H git config --global gc.auto 0

#RUN mkdir /var/lib/gems && chown -R git:git /var/lib/gems/

#Install bundler
RUN gem install bundler --no-ri --no-rdoc

#Install therubyrhino
RUN gem install therubyrhino

#Install Gitlab deps
RUN service redis-server start && service postgresql start && cd /home/git/gitlab && sudo -u git -H bundle install --deployment --without development test mysql aws kerberos

#Install Gitlab
RUN service redis-server start && service postgresql start && cd /home/git/gitlab && sudo -u git -H bundle exec rake gitlab:shell:install REDIS_URL=unix:/var/run/redis/redis.sock RAILS_ENV=production

#Install Gitlab Shell
RUN cd /home/git/gitlab && sudo -u git -H bundle exec rake gitlab:shell:install REDIS_URL=unix:/var/run/redis/redis.sock RAILS_ENV=production SKIP_STORAGE_VALIDATION=true

#RUN cd /home/git && sudo -u git -H git clone https://gitlab.com/gitlab-org/gitlab-workhorse.git && cd gitlab-workhorse && git checkout branch-0.7.1 && make
RUN cd /home/git/gitlab && sudo -u git -H bundle exec rake "gitlab:workhorse:install[/home/git/gitlab-workhorse]" RAILS_ENV=production

#silent setup, thanks to athiele (https://github.com/mattias-ohlsson/gitlab-installer/issues/31)
#Setup Gitlab
RUN service redis-server start && service postgresql start && cd /home/git/gitlab && sudo -u git -H bundle exec rake gitlab:setup RAILS_ENV=production force=yes

#Asset compilation
RUN curl --location https://deb.nodesource.com/setup_7.x | bash -
RUN apt-get install -y nodejs
RUN cd /home/git/gitlab && sudo -u git -H /home/git/.yarn/bin/yarn install --production --pure-lockfile
RUN service redis-server start && service postgresql start && cd /home/git/gitlab && sudo -u git -H bundle exec rake assets:precompile RAILS_ENV=production
RUN service redis-server start && service postgresql start && cd /home/git/gitlab && sudo -u git -H bundle exec rake webpack:compile RAILS_ENV=production

#Install Init File / Gitlab shell config
RUN cp /home/git/gitlab/lib/support/init.d/gitlab /etc/init.d/gitlab && cp /home/git/gitlab/lib/support/init.d/gitlab.default.example /etc/default/gitlab && cat /home/git/gitlab/lib/support/nginx/gitlab | sed "s/server_name YOUR_SERVER_FQDN;/server_name $HOSTNAME;/" | tee /etc/nginx/sites-enabled/gitlab && rm -f /etc/nginx/sites-enabled/default && mv /home/git/gitlab-shell/config.yml /home/git/gitlab/config/gitlab-shell.yml && ln -s /home/git/gitlab/config/gitlab-shell.yml /home/git/gitlab-shell/config.yml

# Making sure the assets are always up to date, if someone is configuring a relative path installation instead of an fqdn installation
CMD cd /home/git/gitlab && echo "precompiling assets..." && sudo -u git -H bundle exec rake assets:clean assets:precompile RAILS_ENV=production && service redis-server start && service postgresql start && service nginx start && service gitlab start && tail -f /var/log/nginx/*.log
WORKDIR /home/git
VOLUME /home/git/repositories /var/lib/postgresql /home/git/gitlab/config /etc/default