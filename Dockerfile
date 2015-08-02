# *. Dockerized-Statoshi: Building an image of Statoshi running on Debian 8
#
# VERSION   0.10.x
# URL				http://statoshi.info


FROM debian:latest
MAINTAINER ArtDodger <info@yabtcn.info>
LABEL statoshi.image-specs="{\"Description\":\"A containerized Statoshi\, a fork of Bitcoin Core\, running on Debian 8 using Docker\",\"Usage\":\"docker run -it -p 80:80 yabtcn\\/statoshi-lite\:latest \\/usr\\/local\\/bin\\/bitcoind \&\",\"License\":\"GPL\",\"Version\":\"0.0.1-beta\"}"




# 0. Update Debian and setting up Debian essentials
#
# VERSION		Latest from package manager
# DOCS			https://registry.hub.docker.com/_/debian


RUN apt-get update
RUN apt-get install -y nano wget
RUN apt-get install -y autoconf autotools-dev build-essential bsdmainutils git libboost-all-dev libssl-dev libtool pkg-config
RUN useradd -d /home/statoshi -m -s /bin/bash -c "Statoshi" -p `openssl passwd -1 statoshi` statoshi
RUN apt-get install -y sudo
RUN echo "statoshi ALL=(ALL) ALL" >> /etc/sudoers
RUN mkdir /home/statoshi/.bitcoin && mkdir /home/statoshi/.scripts && mkdir /home/statoshi/log
RUN cd /home/statoshi/.scripts && wget "http://yabtcn.info/statoshi/bitcoind.check.example" -O bitcoind.check.sh >/dev/null 2>&1 && wget "http://yabtcn.info/statoshi/statsd.check.example" -O statsd.check.sh >/dev/null 2>&1 && wget "http://yabtcn.info/statoshi/systemmetricsd.check.example" -O systemmetricsd.check.sh >/dev/null 2>&1 && chmod +x *.sh
RUN wget "http://yabtcn.info/statoshi/bitcoin.conf.example" -O /home/statoshi/.bitcoin/bitcoin.conf >/dev/null 2>&1
RUN chown statoshi:statoshi -R /home/statoshi
RUN cd /home/statoshi && git clone http://github.com/jlopp/bitcoin-utils
RUN sed -i 's/memory          = psutil.phymem_usage()/memory          = psutil.virtual_memory()/g' /home/statoshi/bitcoin-utils/systemMetricsDaemon.py




# 1. Configurating, compiling and setting up Statoshi from source files
#
# VERSION   Latest from GitHub, master branch
# DOCS			https://github.com/ArtDodger/statoshi


RUN cd /tmp && git clone https://github.com/ArtDodger/statoshi
RUN cd /tmp/statoshi && ./autogen.sh
RUN cd /tmp/statoshi && ./configure --disable-wallet --with-cli --without-gui --enable-hardening --without-miniupnpc
RUN cd /tmp/statoshi && make
RUN cd /tmp/statoshi && make install




# 2. Installing StatsD-stack, StatsD (node.js, npm, forever) and dependencies
# 
# VERSION   Latest from GitHub, master branch
# DOCS			https://github.com/etsy/statsd/blob/master/README.md
# DOCS			https://nodejs.org/documentation
# DOCS			http://blog.nodejitsu.com/keep-a-nodejs-server-up-with-forever


RUN apt-get install -y nodejs npm
RUN npm install forever -g
RUN cd /opt && git clone https://github.com/etsy/statsd
RUN cp /opt/statsd/exampleConfig.js /opt/statsd/config.js && sed -i 's/graphiteHost\: \"graphite.example.com\"/graphiteHost\: \"127.0.0.1\"/g' /opt/statsd/config.js
RUN ln -s ""$(which nodejs)"" /usr/bin/node
RUN /usr/local/bin/forever start -c /usr/bin/nodejs /opt/statsd/stats.js /opt/statsd/config.js




# 3. Installing graphite-stack, graphite (python, pip, whisper, memcached carbon, twisted) and dependencies
#
# VERSION	  Latest from package manager and Python's package index
# DOCS			https://graphite.wikidot.com
# DOCS			https://graphite.readthedocs.org
# DOCS			https://wiki.python.org/moin/FrontPage
# DOCS			https://wiki.python.org/moin/CheeseShopTutorial


RUN apt-get install -y libapache2-mod-wsgi memcached python-cairo python-django python-django-tagging python-memcache python-pip python-pysqlite2 python-simplejson python-twisted
RUN pip install carbon graphite-web psutil 'twisted<12.0' whisper
RUN cd /tmp && git clone https://github.com/WoLpH/python-statsd
RUN cd /tmp/python-statsd && python setup.py install
RUN cp /opt/graphite/conf/graphite.wsgi.example /opt/graphite/conf/graphite.wsgi && cp /opt/graphite/conf/carbon.conf.example /opt/graphite/conf/carbon.conf && cp /opt/graphite/conf/storage-schemas.conf.example /opt/graphite/conf/storage-schemas.conf && cp /opt/graphite/conf/storage-aggregation.conf.example /opt/graphite/conf/storage-aggregation.conf && cp /opt/graphite/webapp/graphite/local_settings.py.example /opt/graphite/webapp/graphite/local_settings.py
RUN sed -i '10,$d' /opt/graphite/conf/storage-schemas.conf
RUN echo "[carbon]\r\npattern = ^carbon\.\r\nretentions = 10:2160,60:10080,600:262974\r\n\r\n[stats]\r\npriority = 110\r\npattern = ^stats\\..*\r\nretentions = 10:2160,60:10080,600:262974\r\n\r\n[default]\r\npattern = .*\r\nretentions = 10:2160,60:10080,600:262974" >> /opt/graphite/conf/storage-schemas.conf
RUN sed -i '/xFilesFactor = 0/c\xFilesFactor = 0.0' /opt/graphite/conf/storage-aggregation.conf
RUN echo "\r\nSECRET_KEY = 'statoshi'\r\nTIME_ZONE = 'UTC'\r\nLOG_RENDERING_PERFORMANCE = True\r\nLOG_CACHE_PERFORMANCE = True\r\nLOG_METRIC_ACCESS = True\r\nMEMCACHE_HOSTS = ['127.0.0.1:11211']\r\nDEFAULT_CACHE_DURATION = 600\r\n# Cache images and data for 10 minutes" >> /opt/graphite/webapp/graphite/local_settings.py
RUN cd /opt/graphite/webapp/graphite && python manage.py syncdb --noinput
RUN cd /opt/graphite/webapp/graphite && echo "from django.contrib.auth.models import User; User.objects.create_superuser('statoshi', 'admin@example.info', 'statoshi')" | python manage.py shell
RUN wget "https://pypi.python.org/packages/source/g/graphite-web/graphite-web-0.9.13.tar.gz" -O /tmp/graphite-web-0.9.13.tar.gz >/dev/null 2>&1
RUN cd /tmp && tar -zxvf /tmp/graphite-web-0.9.13.tar.gz >/dev/null 2>&1
RUN cd /tmp/graphite-web-0.9.13 && python setup.py install




# 4. Installing Apache 2.2 and setting up configuration files
#
# VERSION	  2.4.1-common
# DOCS			https://httpd.apache.org/docs/2.2


RUN apt-get install -y apache2.2-common
RUN wget "http://yabtcn.info/statoshi/000-default.conf.example" -O /etc/apache2/sites-available/000-default.conf >/dev/null 2>&1 && wget "http://yabtcn.info/statoshi/default-ssl.conf.example" -O /etc/apache2/sites-available/default-ssl.conf >/dev/null 2>&1 && wget "http://yabtcn.info/statoshi/graphite.conf.example" -O /etc/apache2/sites-available/graphite.conf >/dev/null 2>&1
RUN cd /opt/graphite/bin && wget "http://yabtcn.info/statoshi/graphite.check.example" -O /opt/graphite/bin/graphite.check.sh >/dev/null 2>&1 && chmod +x graphite.check.sh
RUN a2ensite default-ssl.conf graphite.conf
RUN echo "\r\nServerName localhost\r\n" >> /etc/apache2/apache2.conf
RUN echo "<Directory />\r\nOrder allow,deny\r\nDeny from all\r\nAllow from 127.0.0.1\r\nAllow from 192.168.0.0/24\r\nAllow from 172.17.0.0/16\r\n#Allow from all\r\n</Directory>\r\n" >> /etc/apache2/httpd.conf
RUN a2enmod headers proxy_http ssl wsgi
RUN sed -i 's/Listen 80/Listen 80\nListen 8080/g' /etc/apache2/ports.conf
RUN mkdir /var/httpd && mkdir /var/httpd/wsgi
RUN /opt/graphite/bin/carbon-cache.py start
RUN chown www-data:www-data -R /var/www && chown www-data:www-data -R /var/httpd && chown www-data:www-data -R /opt/graphite
RUN /etc/init.d/apache2 restart




# 5. Installing grafana 2.0 the system metrics daemon and dependencies
#
# VERSION	  2.0.2
# DOCS			http://docs.grafana.org/v2.0


RUN apt-get install -y apt-transport-https
RUN echo "deb https://packagecloud.io/grafana/stable/debian/ wheezy main" >> /etc/apt/sources.list
RUN wget -qO - "https://packagecloud.io/gpg.key" | apt-key add - >/dev/null 2>&1
RUN apt-get update
RUN apt-get install grafana
RUN wget "http://yabtcn.info/statoshi/grafana.home.json.example" -O /usr/share/grafana/public/dashboards/home.json >/dev/null 2>&1 && wget "http://yabtcn.info/statoshi/grafana.defaults.ini.example" -O /usr/share/grafana/conf/defaults.ini >/dev/null 2>&1
RUN wget "http://yabtcn.info/statoshi/grafana.defaults.ini.example" -O /usr/share/grafana/conf/defaults.ini >/dev/null 2>&1
RUN wget "http://statoshi.info/img/statoshi.png" -O /usr/share/grafana/public/img/statoshi.png >/dev/null 2>&1




# 6A. Hardening the Container. After setup of programs, opening ports, setting up ufw, etc.
#
# TODO		  Hardening the system, purge unnecessary packages, setting up iptables


RUN wget "http://yabtcn.info/statoshi/bitcoind.conf.example" -O /etc/default/bitcoind >/dev/null 2>&1 && wget "http://yabtcn.info/statoshi/bitcoind.init.example" -O /etc/init.d/bitcoind >/dev/null 2>&1
RUN chmod +x /etc/init.d/bitcoind
RUN apt-get install -y rcconf sysv-rc-conf cron
RUN update-rc.d bitcoind defaults && update-rc.d grafana-server defaults && update-rc.d cron defaults
RUN rm /etc/crontab && wget "http://yabtcn.info/statoshi/crontab.example" -O /etc/crontab >/dev/null 2>&1
