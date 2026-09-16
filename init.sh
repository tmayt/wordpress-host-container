#!/bin/bash
set -e

STATE_FILE="/var/lib/bootstrap.done"
WP_HTACCESS="/var/www/html/.htaccess"

# Pretty permalinks 404 without rewrite rules. Keep this on every start
# because the html volume can exist without a usable .htaccess.
ensure_wordpress_htaccess() {
    local block
    block="$(cat <<'EOF'
# BEGIN WordPress
<IfModule mod_rewrite.c>
RewriteEngine On
RewriteRule .* - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization}]
RewriteBase /
RewriteRule ^index\.php$ - [L]
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule . /index.php [L]
</IfModule>
# END WordPress

# BEGIN Performance
<IfModule mod_expires.c>
ExpiresActive On
ExpiresByType text/css "access plus 7 days"
ExpiresByType application/javascript "access plus 7 days"
ExpiresByType image/jpeg "access plus 30 days"
ExpiresByType image/png "access plus 30 days"
ExpiresByType image/webp "access plus 30 days"
ExpiresByType image/svg+xml "access plus 30 days"
ExpiresByType font/woff2 "access plus 30 days"
</IfModule>
# END Performance
EOF
)"

    if [ ! -d /var/www/html ]; then
        return 0
    fi

    if [ -f "$WP_HTACCESS" ]; then
        # Drop a previous WordPress/Performance block so a wrong RewriteBase /
        # RewriteEngine Off left on the html volume cannot keep permalinks 404.
        sed -i '/# BEGIN WordPress/,/# END WordPress/d' "$WP_HTACCESS"
        sed -i '/# BEGIN Performance/,/# END Performance/d' "$WP_HTACCESS"
        sed -i '/^[[:space:]]*RewriteEngine[[:space:]]\+Off[[:space:]]*$/d' "$WP_HTACCESS"
        printf '\n%s\n' "$block" >> "$WP_HTACCESS"
        echo "[INIT] Refreshed WordPress .htaccess rewrite rules"
    else
        printf '%s\n' "$block" > "$WP_HTACCESS"
        echo "[INIT] Created WordPress .htaccess for permalinks"
    fi
    chown www-data:www-data "$WP_HTACCESS" 2>/dev/null || true
}

flush_permalinks() {
    if [ ! -f /var/www/html/wp-config.php ]; then
        return 0
    fi

    local i
    for i in $(seq 1 30); do
        if wp db check --allow-root --path=/var/www/html >/dev/null 2>&1; then
            if wp core is-installed --allow-root --path=/var/www/html >/dev/null 2>&1; then
                wp rewrite flush --hard --allow-root --path=/var/www/html >/dev/null 2>&1 || true
                echo "[INIT] Flushed WordPress rewrite rules"
            fi
            return 0
        fi
        sleep 1
    done
    echo "[INIT] Skipped rewrite flush (database not ready)"
}

# Keep wp-config lean: fewer revisions, capped memory, no file editor.
ensure_wp_performance_config() {
    local cfg="/var/www/html/wp-config.php"
    if [ ! -f "$cfg" ]; then
        return 0
    fi

    if grep -q "WP_PERF_TUNING" "$cfg" 2>/dev/null; then
        return 0
    fi

    local block_file
    block_file="$(mktemp)"
    cat > "$block_file" <<'EOF'

/* WP_PERF_TUNING */
define('WP_MEMORY_LIMIT', '128M');
define('WP_MAX_MEMORY_LIMIT', '256M');
define('WP_POST_REVISIONS', 5);
define('EMPTY_TRASH_DAYS', 7);
define('AUTOSAVE_INTERVAL', 120);
define('WP_CRON_LOCK_TIMEOUT', 60);
define('CONCATENATE_SCRIPTS', true);
define('DISALLOW_FILE_EDIT', true);
/* END WP_PERF_TUNING */

EOF

    if grep -q "wp-settings.php" "$cfg"; then
        # Insert immediately before WordPress bootstrap require
        awk -v bf="$block_file" '
            /wp-settings\.php/ && !done {
                while ((getline line < bf) > 0) print line
                close(bf)
                done=1
            }
            { print }
        ' "$cfg" > "${cfg}.tmp" && mv "${cfg}.tmp" "$cfg"
    else
        cat "$block_file" >> "$cfg"
    fi
    rm -f "$block_file"
    echo "[INIT] Applied WordPress performance constants"
}

ensure_wordpress_htaccess
ensure_wp_performance_config

# =========================
# USE ENV (DEFAULTS ONLY IF NOT PROVIDED)
# =========================
: "${DB_NAME:=wordpress}"
: "${DB_USER:=wordpress}"
: "${DB_PASS:=123456}"
: "${DB_ROOT_PASS:=root123456}"
: "${FILEBROWSER_USER:=admin}"
: "${FILEBROWSER_PASS:=admin123@qwe}"

# Keep FileBrowser behind /filebrowser even on upgraded volumes.
FILE_DB="/database/filebrowser.db"
mkdir -p /database
if [ -f "$FILE_DB" ]; then
    /usr/local/bin/filebrowser config set \
        --database "$FILE_DB" \
        --address 127.0.0.1 \
        --port 8080 \
        --baseurl /filebrowser >/dev/null 2>&1 || true
    # Env password only applied on first DB create; re-sync so compose changes work
    /usr/local/bin/filebrowser users update "${FILEBROWSER_USER}" \
        --password "${FILEBROWSER_PASS}" \
        --database "$FILE_DB" >/dev/null 2>&1 || true
fi
chmod 666 "$FILE_DB" 2>/dev/null || true
chmod 777 /database 2>/dev/null || true

# =========================
# FIRST RUN CHECK
# =========================
if [ -f "$STATE_FILE" ]; then
    flush_permalinks
    echo "[INIT] Already initialized. Skipping..."
    exit 0
fi

sleep 10

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
ensure_wp_performance_config

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
mkdir -p /database

if [ ! -f "$FILE_DB" ]; then
    /usr/local/bin/filebrowser config init \
        --database "$FILE_DB" \
        --address 127.0.0.1 \
        --port 8080 \
        --baseurl /filebrowser

    /usr/local/bin/filebrowser users add \
        "${FILEBROWSER_USER}" \
        "${FILEBROWSER_PASS}" \
        --database "$FILE_DB" \
        --perm.admin || true
else
    /usr/local/bin/filebrowser users update "${FILEBROWSER_USER}" \
        --password "${FILEBROWSER_PASS}" \
        --database "$FILE_DB" >/dev/null 2>&1 || \
    /usr/local/bin/filebrowser users add \
        "${FILEBROWSER_USER}" \
        "${FILEBROWSER_PASS}" \
        --database "$FILE_DB" \
        --perm.admin || true
fi
chmod 666 "$FILE_DB" 2>/dev/null || true
chmod 777 /database 2>/dev/null || true

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
echo "Domain       : ${PUBLIC_HOST:-localhost}"
echo "WordPress DB MariaDB"
echo "DB_NAME      : ${DB_NAME}"
echo "DB_USER      : ${DB_USER}"
echo "DB_PASSWORD  : ${DB_PASS}"
echo "DB_ROOT_PASS : ${DB_ROOT_PASS}"
echo ""
echo "FileBrowser"
echo "URL      : http://${PUBLIC_HOST:-localhost}/filebrowser"
echo "USERNAME : ${FILEBROWSER_USER}"
echo "PASSWORD : ${FILEBROWSER_PASS}"
echo ""
echo "phpMyAdmin"
echo "URL      : http://${PUBLIC_HOST:-localhost}/phpmyadmin"
echo "LOGIN    : use DB_USER/DB_PASS or root / DB_ROOT_PASS"
echo "======================================"
echo ""