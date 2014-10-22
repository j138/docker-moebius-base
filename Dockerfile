FROM j138/centos-latest-andmore
MAINTAINER j138
# ENV IP __YOUR_IP_HERE__
ENV IP 192.168.54.100
ENV LOGSERVER 127.0.0.1
ENV USER t00114
ENV PW melody
ENV HOME /root

RUN mkdir -m 700 /root/.ssh

RUN sed -ri "s/^UsePAM yes/#UsePAM yes/" /etc/ssh/sshd_config
RUN sed -ri "s/^#UsePAM no/UsePAM no/" /etc/ssh/sshd_config
RUN sed -rie "9i Allow from $IP" /etc/httpd/conf.d/phpmyadmin.conf
RUN sed -ri "s/cfg\['blowfish_secret'\] = ''/cfg['blowfish_secret'] = '`uuidgen`'/" /usr/share/phpmyadmin/config.inc.php


# sshでログインするユーザーを用意
RUN useradd $USER
RUN echo "$USER:$PW" | chpasswd
RUN echo "$USER ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/$USER

RUN touch /etc/sysconfig/network

RUN /etc/init.d/sshd start && /etc/init.d/sshd stop

# apache
RUN chmod 755 /var/log/httpd
RUN chown apache. /var/log/httpd
RUN echo hello > /var/www/html/index.html


# mysql
ADD ./files/mysql_encoding.cnf /etc/my.cnf.d/

RUN \
  service mysqld start && \
  /usr/bin/mysqladmin -u root password "$PW"


# redis
RUN sed -ri "s/daemonize yes/daemonize no/" /etc/redis.conf


# td-agent
ADD files/td-agent.conf /etc/td-agent/td-agent.conf
RUN sed -ri "s/__YOUR_LOG_SERVER_HERE__/$LOGSERVER/" /etc/td-agent/td-agent.conf
RUN gpasswd -a td-agent apache


# install node.js
RUN npm install -g grunt grunt-cli sass coffee-script bower
RUN npm install -g grunt-bower-task grunt-contrib-csslint grunt-contrib-cssmin grunt-contrib-watch grunt-contrib-uglify grunt-contrib-concat grunt-contrib-compass --save-dev


# install ruby
ENV RBENV_ROOT /usr/local/rbenv
ENV PATH $RBENV_ROOT/bin:$RBENV_ROOT/shims:$PATH
RUN echo "export RBENV_ROOT=$RBENV_ROOT" >> /etc/profile.d/rbenv.sh
RUN echo 'export PATH='$RBENV_ROOT'/bin:$PATH' >> /etc/profile.d/rbenv.sh
RUN echo 'eval "$(rbenv init -)"' >> /etc/profile.d/rbenv.sh

RUN git clone https://github.com/sstephenson/rbenv.git $RBENV_ROOT
RUN git clone https://github.com/sstephenson/ruby-build.git $RBENV_ROOT/plugins/ruby-build
RUN $RBENV_ROOT/plugins/ruby-build/install.sh

RUN \
  rbenv install 2.1.3 ;\
  rbenv global 2.1.3

RUN chown -R apache. $RBENV_ROOT

RUN \
  echo 'gem: --no-rdoc --no-ri' >> /.gemrc ;\
  gem install bundler passenger sensu-plugin redis ruby-supervisor

ADD files/passenger.conf /etc/httpd/conf.d/passenger.conf

RUN \
  eval "$(rbenv init -)" ;\
  passenger-install-apache2-module -a ;\
  passenger-install-apache2-module --snippet >> /etc/httpd/conf.d/passenger.conf


# supervisord
RUN wget http://peak.telecommunity.com/dist/ez_setup.py;python ez_setup.py
RUN easy_install supervisor
RUN mkdir /etc/supervisord/
RUN mkdir /var/log/supervisord
ADD files/supervisord.conf /etc/supervisord.conf


# RabbitMQ
RUN rpm --import http://www.rabbitmq.com/rabbitmq-signing-key-public.asc
RUN rpm -Uvh http://www.rabbitmq.com/releases/rabbitmq-server/v3.1.4/rabbitmq-server-3.1.4-1.noarch.rpm
RUN git clone https://github.com/joemiller/joemiller.me-intro-to-sensu.git
RUN cd joemiller.me-intro-to-sensu/; ./ssl_certs.sh clean && ./ssl_certs.sh generate
RUN mkdir /etc/rabbitmq/ssl
RUN cp /joemiller.me-intro-to-sensu/server_cert.pem /etc/rabbitmq/ssl/cert.pem
RUN cp /joemiller.me-intro-to-sensu/server_key.pem /etc/rabbitmq/ssl/key.pem
RUN cp /joemiller.me-intro-to-sensu/testca/cacert.pem /etc/rabbitmq/ssl/
ADD files/rabbitmq.config /etc/rabbitmq/
RUN sed -ri "s/__PW__/$PW/" /etc/rabbitmq/rabbitmq.config
RUN rabbitmq-plugins enable rabbitmq_management


# Sensu server, uchiwa
ADD files/sensu.repo /etc/yum.repos.d/
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


# jdk
WORKDIR /usr/local/src
RUN curl -L -C - -b "oraclelicense=accept-securebackup-cookie" -O http://download.oracle.com/otn-pub/java/jdk/8u25-b17/jdk-8u25-linux-x64.tar.gz
RUN tar xzf jdk-8u25-linux-x64.tar.gz
WORKDIR cd /usr/local/src/jdk1.8.0_25/
RUN alternatives --install /usr/bin/java java /usr/local/src/jdk1.8.0_25/bin/java 1
RUN echo 1 | alternatives --config java


# elasticsearch
RUN rpm --import http://packages.elasticsearch.org/GPG-KEY-elasticsearch
ADD ./files/elasticsearch.repo /etc/yum.repos.d/
RUN yum -y install elasticsearch

# Use pip to install graphite, carbon, and deps
# RUN \
#   yum --enablerepo=remi,epel,treasuredata install -y \
#   python python-devel python-pip pycairo python-twisted-web python-zope-interface mod_wsgi mod_python python-simplejson python-sqlite2

RUN pip-python install whisper
RUN pip-python install Twisted==14.0.2
RUN pip-python install --install-option="--prefix=/var/lib/graphite" --install-option="--install-lib=/var/lib/graphite/lib" carbon
RUN pip-python install --install-option="--prefix=/var/lib/graphite" --install-option="--install-lib=/var/lib/graphite/webapp" graphite-web

RUN useradd -d /home/graphite -m -s /bin/bash graphite
RUN echo graphite:graphite | chpasswd
RUN echo 'graphite ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers.d/graphite
RUN chmod 0440 /etc/sudoers.d/graphite

## Add graphite config
ENV GRAPHITE_PATH /var/lib/graphite
ADD ./files/initial_data.json $GRAPHITE_PATH/webapp/graphite/initial_data.json
ADD ./files/local_settings.py $GRAPHITE_PATH/webapp/graphite/local_settings.py
ADD ./files/carbon.conf $GRAPHITE_PATH/conf/carbon.conf
ADD ./files/storage-schemas.conf $GRAPHITE_PATH/conf/storage-schemas.conf
ADD ./files/graphite.wsgi $GRAPHITE_PATH/conf/graphite.wsgi
RUN sed -ri "s#__GRAPHITE_PATH__#$GRAPHITE_PATH#" $GRAPHITE_PATH/conf/carbon.conf
RUN sed -ri "s#__GRAPHITE_PATH__#$GRAPHITE_PATH#" $GRAPHITE_PATH/conf/graphite.wsgi
RUN sed -ri "s/LoadModule python_module/#LoadModule python_module/" /etc/httpd/conf.d/python.conf

RUN \
  mkdir -p $GRAPHITE_PATH/storage/whisper ;\
  touch $GRAPHITE_PATH/storage/graphite.db $GRAPHITE_PATH/storage/index ;\
  chown -R apache $GRAPHITE_PATH/storage ;\
  chmod 0775 $GRAPHITE_PATH/storage $GRAPHITE_PATH/storage/whisper ;\
  chmod 0664 $GRAPHITE_PATH/storage/graphite.db

WORKDIR $GRAPHITE_PATH/webapp/graphite
RUN python manage.py syncdb --noinput

# graphite-web
RUN mkdir /etc/httpd/wsgi/
ADD ./files/graphite.conf /etc/httpd/conf.d/graphite.conf
RUN sed -ri "s#__GRAPHITE_PATH__#$GRAPHITE_PATH#" /etc/httpd/conf.d/graphite.conf


# Install & Patch Grafana
RUN \
  git clone https://github.com/grafana/grafana.git /usr/local/grafana && \
  cd /usr/local/grafana && \
  git checkout v1.7.0
WORKDIR /usr/local/graphite

ADD ./files/correctly-show-urlencoded-metrics.patch /usr/local/grafana/correctly-show-urlencoded-metrics.patch
RUN git apply /usr/local/grafana/correctly-show-urlencoded-metrics.patch --directory=/usr/local/grafana

RUN \
  cd /usr/local/grafana &&\
  npm install &&\
  grunt build

EXPOSE 22 80 3000 4567 5671 15672 9001 8080

CMD ["/usr/bin/supervisord"]
