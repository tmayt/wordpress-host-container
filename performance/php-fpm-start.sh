#!/bin/bash
set -euo pipefail
PHP_VER="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')"
mkdir -p /run/php
exec "/usr/sbin/php-fpm${PHP_VER}" --nodaemonize --fpm-config "/etc/php/${PHP_VER}/fpm/php-fpm.conf"
