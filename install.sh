#!/bin/bash

# Website name
SITE_NAME="${1:-auroralife}"

# Generate random passwords
FILEBROWSER_PASS=$(openssl rand -base64 18 | tr -dc 'A-Za-z0-9' | head -c 24)
DB_PASS=$(openssl rand -base64 18 | tr -dc 'A-Za-z0-9' | head -c 24)

# Generate random ports
PORT_HTTP=$(shuf -i 20000-40000 -n 1)
PORT_FILEBROWSER=$(shuf -i 40001-50000 -n 1)
PORT_DB=$(shuf -i 50001-60000 -n 1)

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
      - "${PORT_FILEBROWSER}:8080"
      - "${PORT_DB}:3306"
    environment:
      FILEBROWSER_USER: admin
      FILEBROWSER_PASS: ${FILEBROWSER_PASS}
      DB_NAME: ${SITE_NAME}_db
      DB_USER: ${SITE_NAME}_usr
      DB_PASS: ${DB_PASS}
      DB_ROOT_PASS: ${DB_PASS}
    volumes:
      - wp_html:/var/www/html
      - wp_db:/var/lib/mysql
      - filebrowser_db:/database
      - filebrowser_cfg:/config
    restart: always

volumes:
  wp_html:
  wp_db:
  filebrowser_db:
  filebrowser_cfg:
EOF

echo "docker-compose.yml generated successfully!"
echo
echo "Website Name        : ${SITE_NAME}"
echo "WordPress Port      : ${PORT_HTTP}"
echo "FileBrowser Port    : ${PORT_FILEBROWSER}"
echo "MariaDB Port        : ${PORT_DB}"
echo "phpMyAdmin URL      : http://<host>:${PORT_HTTP}/phpmyadmin"
echo "FileBrowser User    : admin"
echo "FileBrowser Password: ${FILEBROWSER_PASS}"
echo "Database Password   : ${DB_PASS}"