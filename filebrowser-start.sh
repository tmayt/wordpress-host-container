#!/bin/bash
# Wait for init to create the DB, then run FileBrowser on localhost.
# Runs as root (bound to 127.0.0.1 only) to avoid volume ownership races
# between init CLI and the daemon.
set -euo pipefail

DB="/database/filebrowser.db"
mkdir -p /database

echo "[filebrowser] waiting for ${DB}..."
for i in $(seq 1 60); do
    if [ -f "$DB" ]; then
        break
    fi
    sleep 1
done

if [ ! -f "$DB" ]; then
    echo "[filebrowser] ${DB} missing after 60s; initializing empty config"
    /usr/local/bin/filebrowser config init \
        --database "$DB" \
        --address 127.0.0.1 \
        --port 8080 \
        --baseurl /filebrowser \
        --root /
fi

chmod 666 "$DB" 2>/dev/null || true
chmod 777 /database 2>/dev/null || true

# Root is filesystem `/` so operators can edit container configs
# (e.g. /etc/php/*/fpm/php.ini) from FileBrowser, not only WordPress files.
exec /usr/local/bin/filebrowser \
    -a 127.0.0.1 \
    -p 8080 \
    --baseurl /filebrowser \
    --database "$DB" \
    --root /
