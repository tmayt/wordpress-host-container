#!/bin/bash
set -e

STATE_FILE="/var/lib/bootstrap.done"

# =========================
# FIRST RUN CHECK
# =========================
if [ -f "$STATE_FILE" ]; then
    echo "[INIT] Already initialized. Skipping..."
    exit 0
fi

sleep 10

# =========================
# USE ENV (DEFAULTS ONLY IF NOT PROVIDED)
# =========================
: "${DB_NAME:=wordpress}"
: "${DB_USER:=wordpress}"
: "${DB_PASS:=123456}"
: "${DB_ROOT_PASS:=root123456}"
: "${FILEBROWSER_USER:=admin}"
: "${FILEBROWSER_PASS:=admin123@qwe}"

# =========================
# MYSQL SETUP
# =========================
mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASS}';"

mysql -uroot -p${DB_ROOT_PASS} -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME};"

mysql -uroot -p${DB_ROOT_PASS} -e \
"CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';"

mysql -uroot -p${DB_ROOT_PASS} -e \
"GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';"

mysql -uroot -p${DB_ROOT_PASS} -e "FLUSH PRIVILEGES;"

# =========================
# WORDPRESS CONFIG
# =========================
if [ -f /var/www/html/wp-config-sample.php ]; then
    cp /var/www/html/wp-config-sample.php /var/www/html/wp-config.php

    sed -i "s/database_name_here/${DB_NAME}/" /var/www/html/wp-config.php
    sed -i "s/username_here/${DB_USER}/" /var/www/html/wp-config.php
    sed -i "s/password_here/${DB_PASS}/" /var/www/html/wp-config.php
fi

rm -f /var/www/html/index.html || true
chown -R www-data:www-data /var/www/html

# =========================
# MARK INSTALL DONE
# =========================
mkdir -p /var/lib
touch "$STATE_FILE"

# =========================
# FILEBROWSER INIT USER
# =========================

FILE_DB="/database/filebrowser.db"
mkdir /database -p

if [ ! -f "$FILE_DB" ]; then
    mkdir -p /database

    /usr/local/bin/filebrowser config init \
        --database "$FILE_DB" \
        --address 0.0.0.0 \
        --port 8080

    /usr/local/bin/filebrowser users add \
        "${FILEBROWSER_USER}" \
        "${FILEBROWSER_PASS}" \
        --database "$FILE_DB" \
        --perm.admin || true
fi
chown -R www-data:www-data /database

# =========================
# PHPMYADMIN CONFIG
# =========================
PMA_CONFIG="/usr/share/phpmyadmin/config.inc.php"
PMA_TMP="/var/lib/phpmyadmin/tmp"
mkdir -p "$PMA_TMP"
chown -R www-data:www-data /var/lib/phpmyadmin

BLOWFISH=$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 32)

cat > "$PMA_CONFIG" <<EOF
<?php
declare(strict_types=1);

\$cfg['blowfish_secret'] = '${BLOWFISH}';
\$cfg['TempDir'] = '${PMA_TMP}';

\$i = 0;
\$i++;
\$cfg['Servers'][\$i]['auth_type'] = 'cookie';
\$cfg['Servers'][\$i]['host'] = 'localhost';
\$cfg['Servers'][\$i]['compress'] = false;
\$cfg['Servers'][\$i]['AllowNoPassword'] = false;
EOF

chown www-data:www-data "$PMA_CONFIG"
chmod 640 "$PMA_CONFIG"

# =========================
# OUTPUT (ONLY ON FIRST RUN)
# =========================
echo ""
echo "======================================"
echo " FIRST RUN SETUP COMPLETED"
echo "======================================"
echo "WordPress DB MariaDB"
echo "DB_NAME      : ${DB_NAME}"
echo "DB_USER      : ${DB_USER}"
echo "DB_PASSWORD  : ${DB_PASS}"
echo "DB_ROOT_PASS : ${DB_ROOT_PASS}"
echo ""
echo "FileBrowser"
echo "URL      : http://localhost:8080"
echo "USERNAME : ${FILEBROWSER_USER}"
echo "PASSWORD : ${FILEBROWSER_PASS}"
echo ""
echo "phpMyAdmin"
echo "URL      : http://localhost/phpmyadmin"
echo "LOGIN    : use DB_USER/DB_PASS or root / DB_ROOT_PASS"
echo "======================================"
echo ""