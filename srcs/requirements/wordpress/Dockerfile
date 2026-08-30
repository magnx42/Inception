FROM debian:bookworm
RUN apt update -y && apt upgrade -y
RUN apt install wget php php-fpm php-mysql mariadb-client -y
RUN wget https://fr.wordpress.org/wordpress-7.0.4-fr_FR.tar.gz -P /var/www
RUN cd /var/www && tar -xzf wordpress-7.0.4-fr_FR.tar.gz && rm wordpress-7.0.4-fr_FR.tar.gz
RUN chown -R www-data:www-data /var/www/wordpress
COPY conf/php.conf /etc/php/8.2/fpm/pool.d/www.conf
RUN wget https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
RUN chmod +x wp-cli.phar && mv wp-cli.phar /usr/local/bin/wp
COPY conf/auto-config.sh /tmp/auto-config.sh
RUN chmod +x /tmp/auto-config.sh
ENTRYPOINT [ "/tmp/auto-config.sh" ]