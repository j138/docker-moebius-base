FROM centos:centos6
MAINTAINER j138
# ENV IP __YOUR_IP_HERE__
ENV IP 192.168.1.100
ENV USER t00114
ENV PW melody
ENV HOME /root

# package install
RUN yum -y install yum-plugin-fastestmirror
RUN echo "include_only=.jp" >> /etc/yum/pluginconf.d/fastestmirror.conf
RUN yum update -y
RUN yum install wget -y

RUN \
  rpm --import http://rpms.famillecollet.com/RPM-GPG-KEY-remi ;\
  rpm --import http://dl.fedoraproject.org/pub/epel/RPM-GPG-KEY-EPEL-6 ;\
  rpm --import http://apt.sw.be/RPM-GPG-KEY.dag.txt ;\
  rpm -ivh http://dl.fedoraproject.org/pub/epel/6/x86_64/epel-release-6-8.noarch.rpm ;\
  rpm -ivh http://rpms.famillecollet.com/enterprise/remi-release-6.rpm ;\
  rpm -ivh http://pkgs.repoforge.org/rpmforge-release/rpmforge-release-0.5.3-1.el6.rf.x86_64.rpm
ADD files/td.repo /etc/yum.repos.d/td.repo
ADD files/td-agent.conf /etc/td-agent/td-agent.conf

RUN \
  yum --enablerepo=remi,epel,treasuredata install -y \
  sudo which tar bzip2 zip unzip curl-devel git openssh-server openssh-clients syslog gcc gcc-c++ libxml2 libxml2-devel libxslt libxslt-devel readline readline-devel \
  httpd httpd-devel mysql-server mysql-devel phpmyadmin sqlite sqlite-devel redis td-agent \
  php php-devel php-pear php-mysql php-gd php-mbstring php-pecl-imagick php-pecl-memcache nodejs npm erlang \
  sensu uchiwa

RUN mkdir -m 700 /root/.ssh

RUN sed -ri "s/^UsePAM yes/#UsePAM yes/" /etc/ssh/sshd_config
RUN sed -ri "s/^#UsePAM no/UsePAM no/" /etc/ssh/sshd_config
RUN sed -rie "9i Allow from $IP" /etc/httpd/conf.d/phpmyadmin.conf
RUN sed -ri "s/__YOUR_LOG_SERVER_HERE__/$LOGSERVER/" /etc/td-agent/td-agent.conf
RUN sed -ri "s/cfg\['blowfish_secret'\] = ''/cfg['blowfish_secret'] = '`uuidgen`'/" /usr/share/phpmyadmin/config.inc.php


# sshでログインするユーザーを用意
RUN useradd $USER
RUN echo "$USER:$PW" | chpasswd
RUN echo "$USER ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/$USER

RUN touch /etc/sysconfig/network

RUN chmod 755 /var/log/httpd
RUN echo hello > /var/www/html/index.html

RUN \
  service mysqld start && \
  /usr/bin/mysqladmin -u root password "$PW"


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
RUN rabbitmq-plugins enable rabbitmq_management


# Sensu server
ADD ./files/sensu.repo /etc/yum.repos.d/
ADD ./files/config.json /etc/sensu/
RUN mkdir -p /etc/sensu/ssl
RUN cp /joemiller.me-intro-to-sensu/client_cert.pem /etc/sensu/ssl/cert.pem
RUN cp /joemiller.me-intro-to-sensu/client_key.pem /etc/sensu/ssl/key.pem
# uchiwa
ADD ./files/uchiwa.json /etc/sensu/


# supervisord
RUN wget http://peak.telecommunity.com/dist/ez_setup.py;python ez_setup.py
RUN easy_install supervisor
ADD files/supervisord.conf /etc/supervisord.conf

RUN /etc/init.d/sshd start
RUN /etc/init.d/sshd stop

CMD ["/usr/bin/supervisord"]


# install node.js
RUN npm install -g grunt grunt-cli sass coffee-script bower
RUN npm install -g grunt-bower-task grunt-contrib-csslint grunt-contrib-cssmin grunt-contrib-watch grunt-contrib-uglify grunt-contrib-concat grunt-contrib-compass --save-dev


# install ruby
ENV RBENV_ROOT /usr/local/rbenv
ENV PATH $RBENV_ROOT/bin:$PATH
ENV PATH $RBENV_ROOT/shims:$PATH
RUN echo 'eval "$(rbenv init -)"' >> ~/.bashrc
RUN echo 'eval "$(rbenv init -)"' >> /etc/profile.d/rbenv.sh

RUN git clone https://github.com/sstephenson/rbenv.git $RBENV_ROOT
RUN git clone https://github.com/sstephenson/ruby-build.git $RBENV_ROOT/plugins/ruby-build
RUN $RBENV_ROOT/plugins/ruby-build/install.sh

RUN \
  rbenv install 2.1.3 ;\
  rbenv global 2.1.3

RUN \
  echo 'gem: --no-rdoc --no-ri' >> /.gemrc ;\
  gem install bundler passenger

ADD files/passenger.conf /etc/httpd/conf.d/passenger.conf

RUN \
  eval "$(rbenv init -)" ;\
  passenger-install-apache2-module -a ;\
  passenger-install-apache2-module --snippet >> /etc/httpd/conf.d/passenger.conf

EXPOSE 22 80 3000 4567 5671 15672
