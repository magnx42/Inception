#!/bin/sh

set -e

TRIES=0
MAX_TRIES=30

while ! mariadb -h mariadb --connect-timeout=2 -u "$SQL_USER" -p"$SQL_PASSWORD" "$SQL_DATABASE" -e "SELECT 1" >/dev/null 2>&1
do
	TRIES=$((TRIES + 1))
	if [ "$TRIES" -ge "$MAX_TRIES" ]; then
		echo "[entrypoint] base injoignable apres $MAX_TRIES tentatives, abandon" >&2
		exit 1
	fi
	sleep 1
done

echo "[entrypoint] base joignable apres $TRIES tentative(s)"

cd /var/www/wordpress

if ! wp core is-installed --allow-root ; then
    wp config create --allow-root \
        --dbname="$SQL_DATABASE" \
        --dbuser="$SQL_USER" \
        --dbpass="$SQL_PASSWORD" \
        --dbhost="mariadb:3306" \
        --path='/var/www/wordpress' --force

    wp core install --allow-root \
        --url="$SITE_DOMAIN" \
        --title="$SITE_NAME" \
        --admin_user="$SITE_ADMIN_NAME" \
        --admin_password="$SITE_ADMIN_PASS" \
        --admin_email="$SITE_ADMIN_EMAIL" \
        --locale=$LOCALE \
        --skip-email

    wp user create $SITE_USER_NAME $SITE_USER_EMAIL \
        --user_pass="$SITE_USER_PASS" \
        --role=author \
        --allow-root
fi

chown -R www-data:www-data /var/www/wordpress
mkdir -p /run/php
exec /usr/sbin/php-fpm8.2 -F