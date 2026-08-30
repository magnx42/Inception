#!/bin/sh

set -e

: "${SQL_DATABASE:?variable SQL_DATABASE non definie}"
: "${SQL_USER:?variable SQL_USER non definie}"
: "${SQL_PASSWORD:?variable SQL_PASSWORD non definie}"
: "${SQL_ROOT_PASSWORD:?variable SQL_ROOT_PASSWORD non definie}"

mkdir -p /run/mysqld
chown mysql:mysql /run/mysqld

if [ ! -d "/var/lib/mysql/${SQL_DATABASE}" ]; then
	mariadbd --bootstrap --user=mysql <<EOF

FLUSH PRIVILEGES;

CREATE DATABASE IF NOT EXISTS \`${SQL_DATABASE}\`;

CREATE USER '${SQL_USER}'@'%' IDENTIFIED BY '${SQL_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${SQL_DATABASE}\`.* TO '${SQL_USER}'@'%';

ALTER USER 'root'@'localhost' IDENTIFIED BY '${SQL_ROOT_PASSWORD}';

FLUSH PRIVILEGES;
EOF
fi

exec "$@"
