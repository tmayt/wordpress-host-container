#!/bin/bash

# Website name
SITE_NAME="${1:-auroralife}"

# Domain: 2nd arg, SITE_DOMAIN env, or interactive prompt (no IP)
normalize_domain() {
    local d="$1"
    d="${d#http://}"
    d="${d#https://}"
    d="${d%%/*}"
    d="${d%%:*}"
    d="${d%.}"
    printf '%s' "$d" | tr '[:upper:]' '[:lower:]'
}

SITE_DOMAIN="${2:-${SITE_DOMAIN:-}}"
if [ -z "$SITE_DOMAIN" ]; then
    if [ -t 0 ]; then
        echo -n "دامنه سایت را وارد کنید (مثلا example.com): "
        read -r SITE_DOMAIN
    fi
fi

SITE_DOMAIN=$(normalize_domain "$SITE_DOMAIN")
if [ -z "$SITE_DOMAIN" ]; then
    echo "خطا: دامنه الزامی است. مثال:"
    echo "  bash <(curl -fsSL https://gitea.tmayt.ir/thaiostream/wp/raw/branch/main/install.sh) mysite example.com"
    exit 1
fi

# Generate random passwords
FILEBROWSER_PASS=$(openssl rand -base64 18 | tr -dc 'A-Za-z0-9' | head -c 24)
DB_PASS=$(openssl rand -base64 18 | tr -dc 'A-Za-z0-9' | head -c 24)

# Host port for edge → container:80 (not shown in public URLs)
PORT_HTTP=$(shuf -i 20000-40000 -n 1)

# Output file
COMPOSE_FILE="docker-compose.yml"

cat > "$COMPOSE_FILE" <<EOF
services:
  wordpress:
    image: gitea.tmayt.ir/thaiostream/wp
    container_name: ${SITE_NAME}
    build: .
    ports:
      - "${PORT_HTTP}:80"
    environment:
      FILEBROWSER_USER: admin
      FILEBROWSER_PASS: ${FILEBROWSER_PASS}
      DB_NAME: ${SITE_NAME}_db
      DB_USER: ${SITE_NAME}_usr
      DB_PASS: ${DB_PASS}
      DB_ROOT_PASS: ${DB_PASS}
      PUBLIC_HOST: "${SITE_DOMAIN}"
    volumes:
      - wp_html:/var/www/html
      - wp_db:/var/lib/mysql
      - filebrowser_db:/database
      - filebrowser_cfg:/config
      - apache2_data:/etc/php/8.1/apache2
    restart: always
    mem_limit: 1536m
    cpus: 2.0

volumes:
  wp_html:
  wp_db:
  filebrowser_db:
  filebrowser_cfg:
  apache2_data:
EOF

echo "docker-compose.yml generated successfully!"
echo
echo "Website Name           : ${SITE_NAME}"
echo "Domain                 : ${SITE_DOMAIN}"
echo "Docker HTTP port (edge): ${PORT_HTTP}"
echo "WordPress URL          : http://${SITE_DOMAIN}/"
echo "phpMyAdmin URL         : http://${SITE_DOMAIN}/phpmyadmin"
echo "FileBrowser URL        : http://${SITE_DOMAIN}/filebrowser"
echo "FileBrowser User       : admin"
echo "FileBrowser Password   : ${FILEBROWSER_PASS}"
echo "Database Password      : ${DB_PASS}"
echo
echo "After: docker compose up -d --build"
echo "Point your edge/proxy to host port ${PORT_HTTP}."
