FROM gitea.tmayt.ir/thaiostream/ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# ===== Iranian mirror =====
RUN echo "deb http://mirror.arvancloud.ir/ubuntu/ jammy main restricted universe multiverse" > /etc/apt/sources.list \
 && echo "deb http://mirror.arvancloud.ir/ubuntu/ jammy-updates main restricted universe multiverse" >> /etc/apt/sources.list \
 && echo "deb http://mirror.arvancloud.ir/ubuntu/ jammy-backports main restricted universe multiverse" >> /etc/apt/sources.list \
 && echo "deb http://mirror.arvancloud.ir/ubuntu/ jammy-security main restricted universe multiverse" >> /etc/apt/sources.list

# ===== Install all services =====
RUN apt-get update && apt-get install -y \
    apache2 mariadb-server \
    php php-mysql php-cli php-curl php-xml php-mbstring php-zip php-gd libapache2-mod-php \
    wget curl unzip tar openssl supervisor nano \
    && rm -rf /var/lib/apt/lists/*

# ===== Apache VirtualHost (pretty permalinks) =====
COPY apache/000-default.conf /etc/apache2/sites-available/000-default.conf
RUN sed -i '/<Directory \/var\/www\/>/,/<\/Directory>/ s/AllowOverride None/AllowOverride All/' /etc/apache2/apache2.conf \
 && a2enmod rewrite \
 && a2ensite 000-default.conf

# ===== Install phpMyAdmin =====
COPY phpmyadmin /phpmyadmin
RUN chmod +x /phpmyadmin/get.sh \
 && /phpmyadmin/get.sh \
 && cp /phpmyadmin/apache-phpmyadmin.conf /etc/apache2/conf-available/phpmyadmin.conf \
 && a2enconf phpmyadmin

# ===== Install FileBrowser =====
COPY filebrowser /filebrowser
RUN chmod +x /filebrowser/get.sh \
 && /filebrowser/get.sh

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
    echo "zend_extension=$EXT_DIR/$(basename $IONCUBE)" > /etc/php/${PHP_MAJOR}.${PHP_MINOR}/apache2/conf.d/00-ioncube.ini; \
    echo "zend_extension=$EXT_DIR/$(basename $IONCUBE)" > /etc/php/${PHP_MAJOR}.${PHP_MINOR}/cli/conf.d/00-ioncube.ini

# ===== WP-CLI =====
RUN curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
 && chmod +x wp-cli.phar \
 && mv wp-cli.phar /usr/local/bin/wp

EXPOSE 80 8080 3306

CMD ["/usr/bin/supervisord", "-n"]