# Use the official PHP 8.3 Apache image
FROM php:8.3-apache

# Install required system dependencies for Laravel
RUN apt-get update && apt-get install -y \
    libpng-dev \
    libonig-dev \
    libxml2-dev \
    zip \
    unzip \
    git \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install necessary PHP extensions (add others if needed)
RUN docker-php-ext-install pdo_mysql mbstring exif pcntl bcmath gd

# Enable Apache mod_rewrite for Laravel routing
RUN a2enmod rewrite

# Install Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# Set the working directory
WORKDIR /var/www/html

# Copy the application files into the container
COPY . .

# Install Composer dependencies (optimizing for production)
RUN composer install --optimize-autoloader --no-dev

# Set permissions for Laravel's storage and bootstrap cache
RUN chown -R www-data:www-data /var/www/html/storage /var/www/html/bootstrap/cache

# ==========================================
# CLOUD RUN SPECIFIC CONFIGURATION
# ==========================================

# 1. Change Apache Document Root to Laravel's /public folder
ENV APACHE_DOCUMENT_ROOT /var/www/html/public
RUN sed -ri -e 's!/var/www/html!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/sites-available/*.conf
RUN sed -ri -e 's!/var/www/!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/apache2.conf /etc/apache2/conf-available/*.conf

# 2. Configure Apache to listen on the $PORT environment variable
RUN sed -i 's/80/${PORT}/g' /etc/apache2/sites-available/000-default.conf /etc/apache2/ports.conf