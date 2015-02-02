FROM j138/centos-latest-andmore
MAINTAINER j138
# ENV IP __YOUR_IP_HERE__
ENV IP 192.168.54.100
ENV LOGSERVER 127.0.0.1
ENV USER deploy
ENV PW melody
ENV HOME /root
ENV TERM xterm-256color

RUN \
  mkdir -m 700 /root/.ssh; \
  sed -ri "s/^UsePAM yes/#UsePAM yes/" /etc/ssh/sshd_config; \
  sed -ri "s/^#UsePAM no/UsePAM no/" /etc/ssh/sshd_config; \
  localedef -f UTF-8 -i ja_JP ja_JP.utf8; \
  echo 'LANG="ja_JP.UTF-8"' >> /etc/sysconfig/i18n


# sshでログインするユーザーを用意
RUN \
  useradd $USER; \
  gpasswd -a $USER nginx; \
  echo "$USER:$PW" | chpasswd; \
  echo "$USER ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/$USER; \
  touch /etc/sysconfig/network; \
  /etc/init.d/sshd start && /etc/init.d/sshd stop


# apache
RUN \
  rm -rf /var/log/httpd && mkdir /var/log/httpd; \
  echo hello > /var/www/html/index.html; \
  echo hello > /usr/share/nginx/html/healthcheck.html

# mysql
ADD ./files/mysql_encoding.cnf /etc/my.cnf.d/
RUN \
  service mysqld start && \
  /usr/bin/mysqladmin -u root password "$PW"


# jdk
RUN \
  cd /usr/local/src; \
  curl -L -C - -b "oraclelicense=accept-securebackup-cookie" -O http://download.oracle.com/otn-pub/java/jdk/8u25-b17/jdk-8u25-linux-x64.tar.gz; \
  tar xzf jdk-8u25-linux-x64.tar.gz -C /usr/local/src; \
  alternatives --install /usr/bin/java java /usr/local/src/jdk1.8.0_25/bin/java 1; \
  echo 1 | alternatives --config java


# elasticsearch
ADD ./files/elasticsearch.repo /etc/yum.repos.d/
RUN \
  rpm --import http://packages.elasticsearch.org/GPG-KEY-elasticsearch; \
  yum -y install elasticsearch


# redis
RUN sed -ri "s/daemonize yes/daemonize no/" /etc/redis.conf


# td-agent
ADD ./files/td-agent.conf /etc/td-agent/td-agent.conf
RUN \
  sed -ri "s/__YOUR_LOG_SERVER_HERE__/$LOGSERVER/" /etc/td-agent/td-agent.conf; \
  /usr/lib64/fluent/ruby/bin/fluent-gem install fluent-plugin-elasticsearch


# install node.js
RUN \
  npm install -g grunt grunt-cli sass coffee-script bower grunt-bower-task \
  grunt-contrib-csslint grunt-contrib-cssmin grunt-contrib-watch grunt-contrib-uglify grunt-contrib-concat grunt-contrib-compass --save-dev


# install ruby
ENV RBENV_ROOT /usr/local/rbenv
ENV PATH $RBENV_ROOT/bin:$RBENV_ROOT/shims:$PATH
RUN \
  echo "export RBENV_ROOT=$RBENV_ROOT" >> /etc/profile.d/rbenv.sh; \
  echo 'export PATH='$RBENV_ROOT'/bin:$PATH' >> /etc/profile.d/rbenv.sh; \
  echo 'eval "$(rbenv init -)"' >> /etc/profile.d/rbenv.sh

RUN \
  git clone https://github.com/sstephenson/rbenv.git $RBENV_ROOT; \
  git clone https://github.com/sstephenson/ruby-build.git $RBENV_ROOT/plugins/ruby-build; \
  $RBENV_ROOT/plugins/ruby-build/install.sh; \
  git clone https://github.com/ianheggie/rbenv-binstubs.git $RBENV_ROOT/plugins/rbenv-binstubs

RUN \
  rbenv install 2.1.5; \
  rbenv rehash; \
  rbenv global 2.1.5; \
  chmod -R 775 /usr/local/rbenv

RUN \
  echo 'gem: --no-rdoc --no-ri' >> /.gemrc; \
  echo 'gem: --no-rdoc --no-ri' >> /etc/.gemrc; \
  gem install bundler sensu-plugin redis ruby-supervisor rubocop haml-lint; \
  echo "export SECRET_KEY_BASE=__SECRET_KEY_BASE__" >> /etc/profile.d/rails.sh; \
  chmod +x /etc/profile.d/rails.sh; \
  chown -R nginx. $RBENV_ROOT


# RabbitMQ
RUN \
    rpm --import http://www.rabbitmq.com/rabbitmq-signing-key-public.asc; \
    rpm -Uvh http://www.rabbitmq.com/releases/rabbitmq-server/v3.1.4/rabbitmq-server-3.1.4-1.noarch.rpm; \
    git clone https://github.com/joemiller/joemiller.me-intro-to-sensu.git; \
    cd joemiller.me-intro-to-sensu/; ./ssl_certs.sh clean && ./ssl_certs.sh generate; \
    mkdir /etc/rabbitmq/ssl; \
    cp /joemiller.me-intro-to-sensu/server_cert.pem /etc/rabbitmq/ssl/cert.pem; \
    cp /joemiller.me-intro-to-sensu/server_key.pem /etc/rabbitmq/ssl/key.pem; \
    cp /joemiller.me-intro-to-sensu/testca/cacert.pem /etc/rabbitmq/ssl/

ADD ./files/rabbitmq.config /etc/rabbitmq/
RUN \
  sed -ri "s/__PW__/$PW/" /etc/rabbitmq/rabbitmq.config; \
  rabbitmq-plugins enable rabbitmq_management


# Sensu server, uchiwa
ADD ./files/sensu.repo /etc/yum.repos.d/
RUN yum install -y sensu uchiwa
ADD ./files/uchiwa.json /etc/sensu/
ADD ./files/config.json /etc/sensu/
RUN sed -ri "s/__PW__/$PW/" /etc/sensu/config.json
RUN sed -ri "s/EMBEDDED_RUBY=false/EMBEDDED_RUBY=true/" /etc/default/sensu

RUN mkdir -p /etc/sensu/ssl
RUN cp /joemiller.me-intro-to-sensu/client_cert.pem /etc/sensu/ssl/cert.pem
RUN cp /joemiller.me-intro-to-sensu/client_key.pem /etc/sensu/ssl/key.pem


# Sensu plugin
RUN git clone https://github.com/sensu/sensu-community-plugins /usr/local/sensu-community-plugins
WORKDIR /usr/local/sensu-community-plugins
RUN bundle install --path vendor/bundle
RUN mv /etc/sensu/plugins /etc/sensu/plugins.bk
RUN ln -s /usr/local/sensu-community-plugins/plugins /etc/sensu/plugins
RUN find /etc/sensu/plugins/ -name "*.rb" | xargs chmod +x

# conf
ADD ./files/client.json /etc/sensu/conf.d/
ADD ./files/check.json /etc/sensu/conf.d/


# supervisord
RUN \
  wget http://peak.telecommunity.com/dist/ez_setup.py; \
  python ez_setup.py; \
  easy_install supervisor; \
  mkdir /etc/supervisord/ /var/log/supervisord

ADD ./files/supervisord.conf /etc/supervisord.conf


# sensu       : 4567, 5671
# rabbitmq    : 15672
# supervisord : 9001
# nginx       : 8888
EXPOSE 22 80 4567 5671 15672 9001 8888
 
CMD ["/usr/bin/supervisord"]
