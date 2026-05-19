# ─── Stage 1: Install Laravel via Composer ─────────────────────────────────
FROM composer:2.7 AS builder

WORKDIR /app

RUN composer create-project laravel/laravel . --prefer-dist --no-interaction

RUN composer install \
    --no-dev \
    --no-interaction \
    --no-scripts \
    --prefer-dist \
    --optimize-autoloader

# ─── Stage 2: Build frontend assets (Vite) ─────────────────────────────────
FROM node:20-alpine AS frontend

WORKDIR /app

COPY --from=builder /app/package.json /app/package-lock.json /app/vite.config.js ./
COPY --from=builder /app/resources ./resources

RUN npm ci && npm run build

# ─── Stage 3: Production image (PHP-FPM + Nginx via Supervisord) ────────────
FROM php:8.3-fpm-alpine

# System packages & PHP extensions
RUN apk add --no-cache \
        nginx \
        supervisor \
        curl \
        libpng-dev \
        libzip-dev \
        oniguruma-dev \
        icu-dev \
        sqlite \
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
COPY --chown=www-data:www-data --from=frontend /app/public/build ./public/build

ENV DB_CONNECTION=sqlite
ENV DB_DATABASE=/var/www/html/database/database.sqlite

RUN touch database/database.sqlite && \
    php artisan key:generate && \
    php artisan migrate --force && \
    php artisan storage:link && \
    php artisan config:cache && \
    php artisan route:cache && \
    php artisan view:cache

RUN chown -R www-data:www-data storage bootstrap/cache database && \
    chmod -R 775 storage bootstrap/cache database

EXPOSE 80

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]