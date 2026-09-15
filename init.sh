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
EOF
)"

    if [ ! -d /var/www/html ]; then
        return 0
    fi

    if [ -f "$WP_HTACCESS" ]; then
        # Drop a previous WordPress block so a wrong RewriteBase / RewriteEngine Off
        # left on the html volume cannot keep permalinks 404 after an image rebuild.
        sed -i '/# BEGIN WordPress/,/# END WordPress/d' "$WP_HTACCESS"
        sed -i '/^[[:space:]]*RewriteEngine[[:space:]]\+Off[[:space:]]*$/d' "$WP_HTACCESS"
        printf '\n%s\n' "$block" >> "$WP_HTACCESS"
        echo "[INIT] Refreshed WordPress .htaccess rewrite rules"
    else
        printf '%s\n' "$block" > "$WP_HTACCESS"
        echo "[INIT] Created WordPress .htaccess for permalinks"
    fi
    chown www-data:www-data "$WP_HTACCESS" 2>/dev/null || true
}

html_escape() {
    printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e "s/'/\&#39;/g" -e 's/"/\&quot;/g'
}

# Secret credentials HTML under a random filename so it is hard to discover.
write_credentials_page() {
    : "${DB_NAME:=wordpress}"
    : "${DB_USER:=wordpress}"
    : "${DB_PASS:=123456}"
    : "${DB_ROOT_PASS:=root123456}"
    : "${FILEBROWSER_USER:=admin}"
    : "${FILEBROWSER_PASS:=admin123@qwe}"
    : "${PUBLIC_HTTP_PORT:=80}"
    : "${PUBLIC_FILEBROWSER_PORT:=8080}"
    : "${PUBLIC_DB_PORT:=3306}"
    : "${PUBLIC_HOST:=}"

    local token_file="/var/lib/credentials.token"
    mkdir -p /var/lib
    if [ -z "${CREDENTIALS_TOKEN:-}" ]; then
        if [ -f "$token_file" ]; then
            CREDENTIALS_TOKEN=$(tr -d '[:space:]' < "$token_file")
        else
            CREDENTIALS_TOKEN=$(openssl rand -hex 24)
        fi
    fi
    printf '%s\n' "$CREDENTIALS_TOKEN" > "$token_file"

    if [ ! -d /var/www/html ]; then
        return 0
    fi

    local page="/var/www/html/${CREDENTIALS_TOKEN}.html"
    local site_name host_hint
    site_name=$(html_escape "${DB_NAME%_db}")
    [ "$site_name" = "wordpress" ] && site_name="wordpress"
    host_hint=$(html_escape "${PUBLIC_HOST:-localhost}")

    local e_db_name e_db_user e_db_pass e_db_root e_fb_user e_fb_pass
    e_db_name=$(html_escape "$DB_NAME")
    e_db_user=$(html_escape "$DB_USER")
    e_db_pass=$(html_escape "$DB_PASS")
    e_db_root=$(html_escape "$DB_ROOT_PASS")
    e_fb_user=$(html_escape "$FILEBROWSER_USER")
    e_fb_pass=$(html_escape "$FILEBROWSER_PASS")

    local wp_url pma_url fb_url wp_admin_url
    if [ "${PUBLIC_HTTP_PORT}" = "80" ]; then
        wp_url="http://${PUBLIC_HOST:-localhost}/"
        wp_admin_url="http://${PUBLIC_HOST:-localhost}/wp-admin/"
        pma_url="http://${PUBLIC_HOST:-localhost}/phpmyadmin/"
    else
        wp_url="http://${PUBLIC_HOST:-localhost}:${PUBLIC_HTTP_PORT}/"
        wp_admin_url="http://${PUBLIC_HOST:-localhost}:${PUBLIC_HTTP_PORT}/wp-admin/"
        pma_url="http://${PUBLIC_HOST:-localhost}:${PUBLIC_HTTP_PORT}/phpmyadmin/"
    fi
    fb_url="http://${PUBLIC_HOST:-localhost}:${PUBLIC_FILEBROWSER_PORT}/"

    local e_wp_url e_wp_admin e_pma_url e_fb_url
    e_wp_url=$(html_escape "$wp_url")
    e_wp_admin=$(html_escape "$wp_admin_url")
    e_pma_url=$(html_escape "$pma_url")
    e_fb_url=$(html_escape "$fb_url")

    cat > "$page" <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="robots" content="noindex, nofollow, noarchive">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Site credentials — ${site_name}</title>
<style>
  :root { color-scheme: light; --bg:#0f1419; --card:#1a2332; --text:#e7eef8; --muted:#9bb0c9; --accent:#3d9cf0; --ok:#3ecf8e; --line:#2a3a4f; }
  * { box-sizing: border-box; }
  body { margin:0; font-family: ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, sans-serif; background: radial-gradient(1200px 600px at 10% -10%, #1c3350, var(--bg)); color: var(--text); min-height: 100vh; }
  main { max-width: 760px; margin: 0 auto; padding: 2.5rem 1.25rem 3rem; }
  h1 { font-size: 1.5rem; margin: 0 0 .35rem; }
  .sub { color: var(--muted); margin: 0 0 1.5rem; font-size: .95rem; }
  .warn { background: #3a2a14; border: 1px solid #7a5a20; color: #f0d9a0; padding: .85rem 1rem; border-radius: 10px; margin-bottom: 1.25rem; font-size: .9rem; }
  section { background: var(--card); border: 1px solid var(--line); border-radius: 14px; padding: 1.1rem 1.2rem; margin-bottom: 1rem; }
  h2 { margin: 0 0 .75rem; font-size: 1.05rem; color: var(--ok); }
  .row { display: grid; grid-template-columns: 140px 1fr; gap: .4rem .75rem; margin: .35rem 0; font-size: .95rem; }
  .label { color: var(--muted); }
  .value { word-break: break-all; font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; }
  a { color: var(--accent); text-decoration: none; }
  a:hover { text-decoration: underline; }
  .copy { margin-inline-start: .5rem; font-size: .75rem; color: var(--muted); cursor: pointer; border: 1px solid var(--line); background: transparent; border-radius: 6px; padding: .1rem .4rem; }
  footer { color: var(--muted); font-size: .8rem; margin-top: 1.25rem; }
</style>
</head>
<body>
<main>
  <h1>Site credentials</h1>
  <p class="sub">Site: <strong>${site_name}</strong> · Domain: <strong>${host_hint}</strong> · keep this URL private</p>
  <div class="warn">This page uses a secret random filename. Do not share the link. WordPress admin is created on first visit to the site.</div>

  <section>
    <h2>WordPress</h2>
    <div class="row"><span class="label">Site</span><span class="value"><a href="${e_wp_url}">${e_wp_url}</a></span></div>
    <div class="row"><span class="label">Admin</span><span class="value"><a href="${e_wp_admin}">${e_wp_admin}</a></span></div>
    <div class="row"><span class="label">Login</span><span class="value">Set during WordPress install wizard</span></div>
  </section>

  <section>
    <h2>phpMyAdmin</h2>
    <div class="row"><span class="label">URL</span><span class="value"><a href="${e_pma_url}">${e_pma_url}</a></span></div>
    <div class="row"><span class="label">User</span><span class="value">${e_db_user} <button class="copy" type="button" data-copy="${e_db_user}">copy</button></span></div>
    <div class="row"><span class="label">Password</span><span class="value">${e_db_pass} <button class="copy" type="button" data-copy="${e_db_pass}">copy</button></span></div>
    <div class="row"><span class="label">Root user</span><span class="value">root</span></div>
    <div class="row"><span class="label">Root pass</span><span class="value">${e_db_root} <button class="copy" type="button" data-copy="${e_db_root}">copy</button></span></div>
  </section>

  <section>
    <h2>FileBrowser</h2>
    <div class="row"><span class="label">URL</span><span class="value"><a href="${e_fb_url}">${e_fb_url}</a></span></div>
    <div class="row"><span class="label">User</span><span class="value">${e_fb_user} <button class="copy" type="button" data-copy="${e_fb_user}">copy</button></span></div>
    <div class="row"><span class="label">Password</span><span class="value">${e_fb_pass} <button class="copy" type="button" data-copy="${e_fb_pass}">copy</button></span></div>
  </section>

  <section>
    <h2>MariaDB</h2>
    <div class="row"><span class="label">Host</span><span class="value">${host_hint}</span></div>
    <div class="row"><span class="label">Port</span><span class="value">${PUBLIC_DB_PORT}</span></div>
    <div class="row"><span class="label">Database</span><span class="value">${e_db_name} <button class="copy" type="button" data-copy="${e_db_name}">copy</button></span></div>
    <div class="row"><span class="label">User</span><span class="value">${e_db_user} <button class="copy" type="button" data-copy="${e_db_user}">copy</button></span></div>
    <div class="row"><span class="label">Password</span><span class="value">${e_db_pass} <button class="copy" type="button" data-copy="${e_db_pass}">copy</button></span></div>
    <div class="row"><span class="label">Root pass</span><span class="value">${e_db_root} <button class="copy" type="button" data-copy="${e_db_root}">copy</button></span></div>
  </section>

  <footer>Generated on first container boot. All links use domain <code>${host_hint}</code>.</footer>
</main>
<script>
document.querySelectorAll('[data-copy]').forEach(function (btn) {
  btn.addEventListener('click', function () {
    var v = btn.getAttribute('data-copy') || '';
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(v).then(function () { btn.textContent = 'copied'; });
    }
  });
});
</script>
</body>
</html>
EOF

    chown www-data:www-data "$page" 2>/dev/null || true
    chmod 640 "$page" 2>/dev/null || true
    echo "[INIT] Credentials page: ${wp_url}${CREDENTIALS_TOKEN}.html"
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

ensure_wordpress_htaccess

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
# FIRST RUN CHECK
# =========================
if [ -f "$STATE_FILE" ]; then
    write_credentials_page
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

write_credentials_page

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
echo "URL      : http://${PUBLIC_HOST:-localhost}:${PUBLIC_FILEBROWSER_PORT:-8080}"
echo "USERNAME : ${FILEBROWSER_USER}"
echo "PASSWORD : ${FILEBROWSER_PASS}"
echo ""
echo "phpMyAdmin"
echo "URL      : http://${PUBLIC_HOST:-localhost}:${PUBLIC_HTTP_PORT:-80}/phpmyadmin"
echo "LOGIN    : use DB_USER/DB_PASS or root / DB_ROOT_PASS"
if [ -n "${CREDENTIALS_TOKEN:-}" ]; then
    echo ""
    echo "Credentials page"
    echo "URL      : http://${PUBLIC_HOST:-localhost}:${PUBLIC_HTTP_PORT:-80}/${CREDENTIALS_TOKEN}.html"
fi
echo "======================================"
echo ""