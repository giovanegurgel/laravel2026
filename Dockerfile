# ─── Stage 1: Build Laravel app + frontend assets ──────────────────────────
FROM composer:2.7 AS builder

WORKDIR /app

# System dependencies needed for frontend build tools
RUN apk add --no-cache nodejs npm

# Create a fresh Laravel project
RUN composer create-project laravel/laravel . --prefer-dist --no-interaction

# Install production PHP dependencies
RUN composer install \
    --no-dev \
    --no-interaction \
    --no-scripts \
    --prefer-dist \
    --optimize-autoloader

# Build Vite assets in the same builder stage
RUN npm install && npm run build

# ─── Stage 2: Production image (PHP-FPM + Nginx via Supervisord) ───────────
FROM php:8.4-fpm-alpine

RUN apk add --no-cache \
        nginx \
        supervisor \
        curl \
        libpng-dev \
        libzip-dev \
        oniguruma-dev \
        icu-dev \
        sqlite \
        sqlite-dev \
        pkgconf \
    && docker-php-ext-install \
        pdo_sqlite \
        mbstring \
        zip \
        gd \
        intl \
        opcache

COPY docker/nginx/default.conf /etc/nginx/http.d/default.conf
COPY docker/php/php.ini /usr/local/etc/php/conf.d/custom.ini
COPY docker/supervisord.conf /etc/supervisord.conf

WORKDIR /var/www/html

COPY --chown=www-data:www-data --from=builder /app .

ENV DB_CONNECTION=sqlite
ENV DB_DATABASE=/var/www/html/database/database.sqlite

RUN touch database/database.sqlite && \
    php artisan storage:link && \
    chown -R www-data:www-data storage bootstrap/cache database && \
    chmod -R 775 storage bootstrap/cache database

EXPOSE 80

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]