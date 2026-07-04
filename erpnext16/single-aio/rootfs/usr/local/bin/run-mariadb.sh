#!/usr/bin/env bash
set -euo pipefail

exec /usr/sbin/mariadbd --datadir=/var/lib/mysql --user=mysql --socket=/run/mysqld/mysqld.sock
