# -----------------------------------------------------------------------------
# WordPress + Apache + PHP 8.2 with Xdebug 3 and WP-CLI.
#
# Built locally (image: volcan-migration/wp:dev). Used by both wp-origen and
# wp-destino. Runtime config (php.ini, xdebug.ini) is mounted at runtime so
# you can tweak it without rebuilding.
# -----------------------------------------------------------------------------

FROM wordpress:6.7-php8.2-apache

ARG XDEBUG_VERSION=3.4.0

ENV DEBIAN_FRONTEND=noninteractive

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        less \
        default-mysql-client \
        git \
        unzip \
        zip \
        libzip-dev \
        libpng-dev \
        libjpeg-dev \
        libfreetype6-dev \
        libicu-dev \
        libonig-dev \
        ca-certificates \
        curl; \
    rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    docker-php-ext-configure gd --with-freetype --with-jpeg; \
    docker-php-ext-install -j"$(nproc)" \
        bcmath \
        gd \
        intl \
        opcache \
        zip

RUN set -eux; \
    pecl install "xdebug-${XDEBUG_VERSION}"; \
    docker-php-ext-enable xdebug; \
    rm -f /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini

RUN set -eux; \
    a2enmod rewrite headers expires

RUN set -eux; \
    curl -fsSL -o /usr/local/bin/wp \
        https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar; \
    chmod +x /usr/local/bin/wp; \
    /usr/local/bin/wp --info --allow-root >/dev/null
