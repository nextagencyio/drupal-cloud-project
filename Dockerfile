# Use official PHP 8.3 with nginx 
FROM php:8.3-fpm-bookworm

# Install system dependencies
RUN apt-get update && apt-get install -y \
    nginx \
    git \
    curl \
    unzip \
    mariadb-client \
    build-essential \
    wget \
    libpng-dev \
    libonig-dev \
    libxml2-dev \
    libzip-dev \
    libicu-dev \
    libjpeg62-turbo-dev \
    libfreetype6-dev \
    libwebp-dev \
    libmagickwand-dev \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

# Install PHP extensions
# Configure and install GD immediately to ensure flags are applied
RUN docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp \
    && docker-php-ext-install -j$(nproc) gd

# Install other PHP extensions
RUN docker-php-ext-install -j$(nproc) pdo_mysql mysqli mbstring xml zip intl bcmath exif soap opcache

# Install imagick
RUN pecl install imagick && docker-php-ext-enable imagick

# Install Redis PHP extension for caching
RUN pecl install redis \
    && docker-php-ext-enable redis

# Install Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# Install Drush globally
RUN composer global require drush/drush:^13

# Configure PHP for production
RUN echo "memory_limit = 512M" >> /usr/local/etc/php/conf.d/drupal.ini \
    && echo "max_execution_time = 600" >> /usr/local/etc/php/conf.d/drupal.ini \
    && echo "upload_max_filesize = 50M" >> /usr/local/etc/php/conf.d/drupal.ini \
    && echo "post_max_size = 50M" >> /usr/local/etc/php/conf.d/drupal.ini \
    && echo "max_input_vars = 5000" >> /usr/local/etc/php/conf.d/drupal.ini \
    && echo "opcache.enable = 1" >> /usr/local/etc/php/conf.d/drupal.ini \
    && echo "opcache.memory_consumption = 192" >> /usr/local/etc/php/conf.d/drupal.ini \
    && echo "opcache.jit=0" >> /usr/local/etc/php/conf.d/drupal.ini \
    && echo "opcache.jit_buffer_size=0" >> /usr/local/etc/php/conf.d/drupal.ini \
    && echo "opcache.enable_cli=1" >> /usr/local/etc/php/conf.d/drupal.ini

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 🚀 OPTIMIZATION: Pre-build Drupal with vendor/ directory
# This eliminates 15+ minute composer install from init containers!
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Build code in /opt/drupal-template (init containers will copy from here)
WORKDIR /opt/drupal-template

# Copy composer files first (better layer caching)
COPY composer.json composer.lock ./

# Pre-install dependencies (15+ minutes, but only once!)
RUN COMPOSER_MEMORY_LIMIT=-1 composer install \
    --no-interaction \
    --no-dev \
    --optimize-autoloader \
    --no-scripts

# Copy rest of the code
COPY . .

# Run composer post-install scripts
RUN COMPOSER_MEMORY_LIMIT=-1 composer run-script post-install-cmd || true

# Set permissions
RUN chown -R www-data:www-data /opt/drupal-template

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Runtime working directory
WORKDIR /var/www/html

# Create directories
RUN mkdir -p /var/www/html/web/sites/default/files /var/www/html/private \
    && chown -R www-data:www-data /var/www/html

# Configure nginx
COPY docker/nginx.conf /etc/nginx/sites-available/default

# Startup script
COPY docker/start.sh /start.sh
RUN chmod +x /start.sh

EXPOSE 80
CMD ["/start.sh"]
