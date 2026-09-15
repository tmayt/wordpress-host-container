# WordPress All-in-One Docker Image

A single Docker container that runs a full WordPress stack: **Apache**, **MariaDB**, **WordPress**, **FileBrowser** (web file manager), **phpMyAdmin** (database UI), **WP-CLI**, and **ionCube Loader** for PHP. Everything is managed by **Supervisor** inside one image, tuned for use on Iranian mirrors (Arvan Cloud Ubuntu).

Use this when you want WordPress up quickly without installing PHP, MySQL, and Apache on the host—only Docker is required.

---

## What is included?

| Component | Role | How you access it |
|-----------|------|-------------------|
| **WordPress** | CMS / website | `http://<domain>/` |
| **Apache** | Web server | Port `80` inside the container |
| **MariaDB** | Database | `localhost:3306` inside the container; optional host port mapping |
| **phpMyAdmin** | Manage MariaDB in the browser | `http://<domain>/phpmyadmin` |
| **FileBrowser** | Edit files under `/var/www/html` | `http://<domain>/filebrowser` |
| **WP-CLI** | WordPress command line | `docker exec -it <container> wp ...` |
| **ionCube Loader** | Run ionCube-encoded PHP plugins/themes | Enabled in PHP automatically |

On first start, `init.sh` creates the database, WordPress `wp-config.php`, FileBrowser admin user, and phpMyAdmin config. This runs **once** per container (tracked by `/var/lib/bootstrap.done`).

---

## Quick install (recommended)

Generate a `docker-compose.yml` with random ports and passwords:

```bash
bash <(curl -fsSL https://gitea.tmayt.ir/thaiostream/wp/raw/branch/main/install.sh) mysite example.com
```

Replace `mysite` with your site name and `example.com` with your domain. If you omit the domain, the script asks for it interactively.

Then build and start:

```bash
docker compose build
docker compose up -d
```

The script prints domain-based URLs (no port in the link) and a private credentials page—**save that output**. Example:

```
Website Name           : mysite
Domain                 : example.com
Docker HTTP port (edge): 28431
Docker MariaDB port    : 52388
WordPress URL          : http://example.com/
phpMyAdmin URL         : http://example.com/phpmyadmin
FileBrowser URL        : http://example.com/filebrowser
...
Credentials page       : http://example.com/<random>.html
```

Point your edge/proxy at the Docker HTTP port. The credentials HTML is created on first container boot under a random filename.
---

## Manual install (clone repo)

### Requirements

- Docker and Docker Compose
- Files in this repo used at build time:
  - `wordpress-6.9.4.tar.gz`
  - `filebrowser/linux-amd64-filebrowser.tar.gz`
  - `phpmyadmin/phpMyAdmin-5.2.3-all-languages.tar.gz`
  - `ioncube/` loader `.so` files for your PHP version

### Steps

```bash
git clone https://gitea.tmayt.ir/thaiostream/wp.git
cd wp
docker compose build
docker compose up -d
```

Default ports in the bundled `docker-compose.yml`:

| Service | Host port | URL |
|---------|-----------|-----|
| WordPress + phpMyAdmin + FileBrowser | `80` | `http://localhost/`, `/phpmyadmin`, `/filebrowser` |
| MariaDB (optional external access) | not exposed by default | use `docker exec` or add `3306:3306` |

View first-run credentials in logs:

```bash
docker compose logs wordpress
```

Look for the `FIRST RUN SETUP COMPLETED` block.

---

## Environment variables

Set these in `docker-compose.yml` under `environment:`:

| Variable | Description | Default (if unset) |
|----------|-------------|----------------------|
| `DB_NAME` | WordPress database name | `wordpress` |
| `DB_USER` | WordPress DB user | `wordpress` |
| `DB_PASS` | WordPress DB password | `123456` |
| `DB_ROOT_PASS` | MariaDB `root` password | `root123456` |
| `FILEBROWSER_USER` | FileBrowser login | `admin` |
| `FILEBROWSER_PASS` | FileBrowser password | `admin123@qwe` |

**Change defaults before production.** The sample `docker-compose.yml` uses weak passwords for local testing only.

---

## Logging in

### WordPress

Open the HTTP port in your browser and complete the WordPress installation wizard. The database is already configured in `wp-config.php`.

### phpMyAdmin

URL: `http://<domain>/phpmyadmin`

Sign in with either:

- **Application user:** `DB_USER` / `DB_PASS`
- **Root:** `root` / `DB_ROOT_PASS`

### FileBrowser

URL: `http://<domain>/filebrowser`

Use `FILEBROWSER_USER` / `FILEBROWSER_PASS`. Root directory is `/var/www/html` (WordPress files). FileBrowser runs on localhost inside the container and is reverse-proxied by Apache.

### WP-CLI

```bash
docker exec -it wp wp plugin list --allow-root
```

Replace `wp` with your `container_name` if you used `install.sh` with a custom site name.

---

## Data persistence

Docker volumes keep data across restarts:

| Volume | Contents |
|--------|----------|
| `wp_html` | WordPress files (`/var/www/html`) |
| `wp_db` | MariaDB data (`/var/lib/mysql`) |
| `filebrowser_db` | FileBrowser database |
| `filebrowser_cfg` | FileBrowser config |

Removing volumes deletes your site and database:

```bash
docker compose down -v   # destructive
```

---

## Building the image yourself

```bash
docker build -t gitea.tmayt.ir/thaiostream/wp .
```

The image is based on Ubuntu 22.04, uses the Arvan Cloud apt mirror, and bundles offline archives from `wordpress/`, `filebrowser/`, and `phpmyadmin/` so the build does not need to download them from the internet (except WP-CLI during build).

---

## Project layout

```
.
├── Dockerfile              # Image definition
├── docker-compose.yml      # Default stack (or generated by install.sh)
├── init.sh                 # First-run DB, WordPress, FileBrowser, phpMyAdmin setup
├── install.sh              # Generates docker-compose with random ports/passwords
├── supervisord.conf        # Runs Apache, MariaDB, FileBrowser, init
├── apache/                 # Apache VirtualHost (WordPress permalinks)
├── wordpress-*.tar.gz      # WordPress source (bundled)
├── wordpress/.htaccess     # Default pretty-permalink rewrite rules
├── filebrowser/            # FileBrowser binary + install script
├── phpmyadmin/             # phpMyAdmin archive + Apache config
└── ioncube/                # ionCube PHP loaders
```

---

## Security notes

- Do not expose MariaDB (`3306`) to the public internet unless you use a firewall and strong passwords.
- phpMyAdmin and FileBrowser are powerful; protect them with strong passwords and, if possible, restrict access by IP or reverse proxy auth.
- After first boot, change default passwords in `docker-compose.yml` and recreate the stack only if you understand that DB users may already exist in the volume.

---

## Troubleshooting

| Problem | What to try |
|---------|-------------|
| Blank page or 502 | Wait ~15s after start; check `docker compose logs` for MariaDB/Apache errors |
| Inner pages / posts return 404 | Rebuild **and recreate** the container (`docker compose up -d --build --force-recreate`). Do not wipe volumes. An old `wp_html` `.htaccess` can disable Directory rewrite; the image now rewrites at VirtualHost level so that cannot 404 inner pages. Then open Settings → Permalinks and Save, or `docker exec <container> wp rewrite flush --hard --allow-root`. |
| Forgot passwords | Read env from `docker-compose.yml` or first-run logs; reset FileBrowser with `filebrowser users` inside the container |
| Re-run first-time setup | Remove the container **and** volumes, then `up` again (wipes data) |
| ionCube build fails | Ensure the matching `ioncube_loader_lin_X.Y.so` exists in `ioncube/` for the PHP version in the image |

---

## License / components

- [WordPress](https://wordpress.org/) — GPL
- [phpMyAdmin](https://www.phpmyadmin.net/) — GPL
- [FileBrowser](https://github.com/filebrowser/filebrowser) — Apache 2.0
- [ionCube Loader](https://www.ioncube.com/) — see `ioncube/LICENSE.txt`
