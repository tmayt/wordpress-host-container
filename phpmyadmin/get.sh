#!/usr/bin/env bash
set -euo pipefail

PMA_ARCHIVE="/phpmyadmin/phpMyAdmin-5.2.3-all-languages.tar.gz"
PMA_INSTALL="/usr/share/phpmyadmin"
PMA_EXTRACT="phpMyAdmin-5.2.3-all-languages"

if [ ! -f "$PMA_ARCHIVE" ]; then
    echo "Aborted: missing $PMA_ARCHIVE"
    exit 1
fi

rm -rf "$PMA_INSTALL" "/tmp/${PMA_EXTRACT}"
mkdir -p "$PMA_INSTALL"

tar -xzf "$PMA_ARCHIVE" -C /tmp
mv "/tmp/${PMA_EXTRACT}"/* "$PMA_INSTALL/"
rm -rf "/tmp/${PMA_EXTRACT}"

mkdir -p /var/lib/phpmyadmin/tmp
chown -R www-data:www-data "$PMA_INSTALL" /var/lib/phpmyadmin

echo "phpMyAdmin installed to $PMA_INSTALL"
