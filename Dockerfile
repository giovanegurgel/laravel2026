# ─── Stage 1: Install Laravel via Composer ─────────────────────────────────
FROM composer:2.7 AS builder

WORKDIR /app

# Create a fresh Laravel project
RUN composer create-project laravel/laravel . --prefer-dist --no-interaction

# Remove dev dependencies, optimise autoloader
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
    && docker-php-ext-install \
        pdo_mysql \
        mbstring \
        zip \
        gd \
        intl \
        opcache

# ── Nginx config ────────────────────────────────────────────────────────────
RUN mkdir -p /etc/nginx/http.d
COPY docker/nginx/default.conf /etc/nginx/http.d/default.conf

# ── PHP tuning ───────────────────────────────────────────────────────────────
COPY docker/php/php.ini /usr/local/etc/php/conf.d/custom.ini

# ── Supervisord config ───────────────────────────────────────────────────────
COPY docker/supervisord.conf /etc/supervisord.conf

# ── Laravel app ─────────────────────────────────────────────────────────────
WORKDIR /var/www/html

# Copy the full Laravel install from Stage 1
COPY --chown=www-data:www-data --from=builder /app .

# Overlay the compiled Vite assets from Stage 2
COPY --chown=www-data:www-data --from=frontend /app/public/build ./public/build

# Generate an APP_KEY and run Laravel bootstrap caches
# APP_KEY can be overridden at runtime via environment variable
RUN php artisan key:generate && \
    php artisan storage:link && \
    php artisan config:cache && \
    php artisan route:cache && \
    php artisan view:cache

# Fix storage permissions
RUN chown -R www-data:www-data storage bootstrap/cache && \
    chmod -R 775 storage bootstrap/cache

EXPOSE 80

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]