FROM gitea.tmayt.ir/thaiostream/ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# ===== Iranian mirror =====
RUN echo "deb http://mirror.arvancloud.ir/ubuntu/ jammy main restricted universe multiverse" > /etc/apt/sources.list \
 && echo "deb http://mirror.arvancloud.ir/ubuntu/ jammy-updates main restricted universe multiverse" >> /etc/apt/sources.list \
 && echo "deb http://mirror.arvancloud.ir/ubuntu/ jammy-backports main restricted universe multiverse" >> /etc/apt/sources.list \
 && echo "deb http://mirror.arvancloud.ir/ubuntu/ jammy-security main restricted universe multiverse" >> /etc/apt/sources.list

# ===== Install all services (PHP-FPM instead of mod_php) =====
RUN apt-get update && apt-get install -y --no-install-recommends \
    apache2 mariadb-server \
    php php-fpm php-mysql php-cli php-curl php-xml php-mbstring php-zip php-gd php-opcache \
    wget curl unzip tar openssl supervisor ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# ===== Apache: event MPM + FPM + compression/cache =====
COPY apache/000-default.conf /etc/apache2/sites-available/000-default.conf
COPY performance/apache-mpm.conf /etc/apache2/conf-available/mpm-tuning.conf
COPY performance/apache-performance.conf /etc/apache2/conf-available/performance.conf
COPY performance/apache-php-fpm.conf /etc/apache2/conf-available/php-fpm.conf
RUN set -eux; \
    # PHP mod_* pins mpm_prefork — disable PHP SAPIs first, then switch MPM
    a2dismod php8.1 2>/dev/null || true; \
    a2dismod php8.2 2>/dev/null || true; \
    a2dismod php8.3 2>/dev/null || true; \
    a2dismod mpm_prefork; \
    a2enmod mpm_event; \
    a2enmod rewrite proxy proxy_http proxy_fcgi setenvif headers deflate expires; \
    a2enconf mpm-tuning performance php-fpm; \
    sed -i '/<Directory \/var\/www\/>/,/<\/Directory>/ s/AllowOverride None/AllowOverride All/' /etc/apache2/apache2.conf; \
    a2ensite 000-default.conf; \
    sed -i 's|^ErrorLog .*|ErrorLog ${APACHE_LOG_DIR}/error.log|' /etc/apache2/apache2.conf

# ===== PHP performance (OPcache + runtime) =====
COPY performance/php-performance.ini /tmp/php-performance.ini
COPY performance/php-opcache.ini /tmp/php-opcache.ini
COPY performance/php-fpm-pool.conf /tmp/php-fpm-pool.conf
COPY performance/php-fpm-start.sh /usr/local/bin/php-fpm-start.sh
RUN set -eux; \
    PHP_VER="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')"; \
    cp /tmp/php-performance.ini "/etc/php/${PHP_VER}/fpm/conf.d/99-performance.ini"; \
    cp /tmp/php-performance.ini "/etc/php/${PHP_VER}/cli/conf.d/99-performance.ini"; \
    cp /tmp/php-opcache.ini "/etc/php/${PHP_VER}/fpm/conf.d/10-opcache-tune.ini"; \
    cp /tmp/php-opcache.ini "/etc/php/${PHP_VER}/cli/conf.d/10-opcache-tune.ini"; \
    cp /tmp/php-fpm-pool.conf "/etc/php/${PHP_VER}/fpm/pool.d/www.conf"; \
    chmod +x /usr/local/bin/php-fpm-start.sh; \
    mkdir -p /run/php

# ===== MariaDB low-memory tuning =====
COPY performance/mariadb.cnf /etc/mysql/mariadb.conf.d/99-performance.cnf

# ===== Install phpMyAdmin =====
COPY phpmyadmin /phpmyadmin
RUN chmod +x /phpmyadmin/get.sh \
 && /phpmyadmin/get.sh \
 && cp /phpmyadmin/apache-phpmyadmin.conf /etc/apache2/conf-available/phpmyadmin.conf \
 && a2enconf phpmyadmin

# ===== Install FileBrowser (proxied at /filebrowser) =====
COPY filebrowser /filebrowser
RUN chmod +x /filebrowser/get.sh \
 && /filebrowser/get.sh \
 && cp /filebrowser/apache-filebrowser.conf /etc/apache2/conf-available/filebrowser.conf \
 && a2enconf filebrowser

# ===== WordPress =====
COPY wordpress-6.9.4.tar.gz /tmp/latest.tar.gz
COPY wordpress/.htaccess /tmp/wordpress.htaccess
RUN cd /tmp \
 && tar -xzf latest.tar.gz \
 && mv wordpress/* /var/www/html/ \
 && rm -f /var/www/html/index.html \
 && cp /tmp/wordpress.htaccess /var/www/html/.htaccess

# ===== Permissions =====
RUN chown -R www-data:www-data /var/www/html

# ===== Supervisor config =====
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# ===== FileBrowser start wrapper =====
COPY filebrowser-start.sh /usr/local/bin/filebrowser-start.sh
RUN chmod +x /usr/local/bin/filebrowser-start.sh

# ===== Init script =====
COPY init.sh /init.sh
RUN chmod +x /init.sh

# ===== IonCube Loader =====
COPY ioncube /ioncube

RUN set -eux; \
    PHP_MAJOR=$(php -r "echo PHP_MAJOR_VERSION;"); \
    PHP_MINOR=$(php -r "echo PHP_MINOR_VERSION;"); \
    EXT_DIR=$(php -i | awk -F'=> ' '/extension_dir/ {print $2}' | head -n1 | tr -d ' '); \
    echo "PHP: ${PHP_MAJOR}.${PHP_MINOR} EXT: ${EXT_DIR}"; \
    if [ -f "/ioncube/ioncube_loader_lin_${PHP_MAJOR}.${PHP_MINOR}.so" ]; then \
        IONCUBE="/ioncube/ioncube_loader_lin_${PHP_MAJOR}.${PHP_MINOR}.so"; \
    elif [ -f "/ioncube/ioncube_loader_lin_${PHP_MAJOR}.${PHP_MINOR}_ts.so" ]; then \
        IONCUBE="/ioncube/ioncube_loader_lin_${PHP_MAJOR}.${PHP_MINOR}_ts.so"; \
    else \
        echo "❌ No matching ionCube loader found"; \
        ls /ioncube; \
        exit 1; \
    fi; \
    cp "$IONCUBE" "$EXT_DIR/"; \
    for sapi in apache2 cli fpm; do \
        confdir="/etc/php/${PHP_MAJOR}.${PHP_MINOR}/${sapi}/conf.d"; \
        if [ -d "$confdir" ]; then \
            echo "zend_extension=$EXT_DIR/$(basename $IONCUBE)" > "$confdir/00-ioncube.ini"; \
        fi; \
    done

# ===== WP-CLI =====
RUN curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
 && chmod +x wp-cli.phar \
 && mv wp-cli.phar /usr/local/bin/wp

EXPOSE 80

CMD ["/usr/bin/supervisord", "-n"]
