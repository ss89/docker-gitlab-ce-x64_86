FROM ubuntu:16.04
MAINTAINER docker@x2d2.de
EXPOSE 80

RUN apt update
RUN apt-get install -y ruby git logrotate libxml2 cmake pkg-config openssl libicu55 python2.7 python-setuptools curl golang postgresql sudo redis-server ruby-dev libicu-dev libpq-dev ruby-execjs nginx
RUN easy_install pip && pip install pygments
RUN curl -O https://kent.dl.sourceforge.net/project/docutils/docutils/0.13.1/docutils-0.13.1.tar.gz && gunzip -c docutils-0.13.1.tar.gz | tar xopf - && cd docutils-0.13.1 && python setup.py install
RUN useradd git && mkdir -p /home/git/repositories && chown -R git:git /home/git
RUN service postgresql start && sudo -u postgres -i psql -d postgres -c "CREATE USER git;" && sudo -u postgres -i psql -d postgres -c "CREATE DATABASE  gitlabhq_production OWNER git;" && sudo -u postgres -i psql -d postgres -c "GRANT ALL PRIVILEGES ON  DATABASE gitlabhq_production to git;" && sudo -u postgres -i psql -d postgres -c "ALTER USER git CREATEDB;" && sudo -u postgres -i psql -d postgres -c "ALTER DATABASE gitlabhq_production owner to git;" && sudo -u postgres -i psql -d postgres -c "ALTER USER git WITH SUPERUSER;"
RUN cp /etc/redis/redis.conf /etc/redis/redis.conf.bak && sed 's/^port .*/port 0/' /etc/redis/redis.conf.bak | sed 's/# unixsocket/unixsocket/' | sed 's/unixsocketperm 700/unixsocketperm 777/' | tee /etc/redis/redis.conf
RUN cd /home/git && sudo -u git -H git clone https://gitlab.com/gitlab-org/gitlab-ce.git -b master gitlab
RUN sudo -u git -H cp /home/git/gitlab/config/gitlab.yml.example /home/git/gitlab/config/gitlab.yml && sudo -u git -H cat /home/git/gitlab/config/gitlab.yml.example | sed 's/port: 80 /port: 8080 /' | tee /home/git/gitlab/config/gitlab.yml && sudo -u git -H cp /home/git/gitlab/config/secrets.yml.example /home/git/gitlab/config/secrets.yml && sudo -u git -H cp /home/git/gitlab/config/unicorn.rb.example /home/git/gitlab/config/unicorn.rb && sudo -u git -H cp /home/git/gitlab/config/initializers/rack_attack.rb.example /home/git/gitlab/config/initializers/rack_attack.rb && sudo -u git -H cat /home/git/gitlab/config/resque.yml.example | sed 's/unix:\/var\/run\/redis\/redis.sock/unix:\/tmp\/redis.sock/' | sudo -u git -H tee /home/git/gitlab/config/resque.yml && sudo -u git -H cat /home/git/gitlab/config/database.yml.postgresql | head -n 8 | sed 's/pool: 10/pool: 10\n  template: template0/' | sudo -u git -H tee /home/git/gitlab/config/database.yml && chmod o-rwx /home/git/gitlab/config/database.yml
RUN sudo -u git -H chmod 0600 /home/git/gitlab/config/secrets.yml && sudo chown -R git /home/git/gitlab/log/ && sudo chown -R git /home/git/gitlab/tmp/ && sudo chmod -R u+rwX,go-w /home/git/gitlab/log/ && sudo chmod -R u+rwX /home/git/gitlab/tmp/ && sudo chmod -R u+rwX /home/git/gitlab/tmp/pids/ && sudo chmod -R u+rwX /home/git/gitlab/tmp/sockets/ && mkdir /home/git/gitlab/public/uploads && chown -R git:git /home/git && sudo chmod 0700 /home/git/gitlab/public/uploads && sudo chmod -R u+rwX /home/git/gitlab/builds/
RUN sudo -u git -H git config --global core.autocrlf input && sudo -u git -H git config --global gc.auto 0
RUN chown -R git:git /var/lib/gems/
RUN gem install bundler --no-ri --no-rdoc
RUN gem install therubyrhino
RUN service redis-server start && service postgresql start && cd /home/git/gitlab && sudo -u git -H bundle install --deployment --without development test mysql aws kerberos
RUN service redis-server start && service postgresql start && cd /home/git/gitlab && sudo -u git -H bundle exec rake gitlab:shell:install REDIS_URL=unix:/tmp/redis.sock RAILS_ENV=production
RUN cd /home/git && sudo -u git -H git clone https://gitlab.com/gitlab-org/gitlab-workhorse.git -b master && cd gitlab-workhorse && make
#silent setup, thanks to athiele (https://github.com/mattias-ohlsson/gitlab-installer/issues/31)
RUN service redis-server start && service postgresql start && cd /home/git/gitlab && sudo -u git -H bundle exec rake gitlab:setup RAILS_ENV=production force=yes
RUN service redis-server start && service postgresql start && cd /home/git/gitlab && sudo -u git -H bundle exec rake assets:precompile RAILS_ENV=production
RUN cp /home/git/gitlab/lib/support/init.d/gitlab /etc/init.d/gitlab && cp /home/git/gitlab/lib/support/init.d/gitlab.default.example /etc/default/gitlab && cat /home/git/gitlab/lib/support/nginx/gitlab | sed "s/server_name YOUR_SERVER_FQDN;/server_name $HOSTNAME;/" | tee /etc/nginx/sites-enabled/gitlab && rm -f /etc/nginx/sites-enabled/default && mv /home/git/gitlab-shell/config.yml /home/git/gitlab/config/gitlab-shell.yml && ln -s /home/git/gitlab/config/gitlab-shell.yml /home/git/gitlab-shell/config.yml
# Making sure the assets are always up to date, if someone is configuring a relative path installation instead of an fqdn installation
CMD cd /home/git/gitlab && echo "precompiling assets..." && sudo -u git -H bundle exec rake assets:clean assets:precompile RAILS_ENV=production && service redis-server start && service postgresql start && service nginx start && service gitlab start && tail -f /var/log/nginx/*.log
WORKDIR /home/git
VOLUME /home/git/repositories /var/lib/postgresql /home/git/gitlab/config /etc/default