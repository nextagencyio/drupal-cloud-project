# Use official PHP 8.3 with nginx 
FROM php:8.3-fpm-bookworm

# Install system dependencies matching your current server
RUN apt-get update && apt-get install -y \
    nginx \
    git \
    curl \
    unzip \
    mariadb-client \
    # libsqlite3-dev removed - using MySQL only \
    build-essential \
    wget \
    libpng-dev \
    libonig-dev \
    libxml2-dev \
    libzip-dev \
    libicu-dev \
    libjpeg62-turbo-dev \
    libfreetype6-dev \
    libmagickwand-dev \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

# SQLite removed - using MySQL for production

# Install PHP extensions in separate steps to help with debugging
RUN docker-php-ext-configure gd --with-freetype --with-jpeg

# Install core extensions first (excluding opcache for now)
RUN docker-php-ext-install -j$(nproc) \
        # pdo_sqlite removed - using MySQL only \
        pdo_mysql \
        mysqli \
        mbstring \
        xml \
        zip \
        intl \
        bcmath \
        exif \
        soap

# Install OPcache (configure JIT via INI instead of build flag)
RUN docker-php-ext-install opcache

# Install GD extension separately (often problematic)
RUN docker-php-ext-install -j$(nproc) gd

# Note: iconv, curl, fileinfo are already included in PHP 8.3
# SQLite extensions removed - using MySQL for production

# Install imagick
RUN pecl install imagick \
    && docker-php-ext-enable imagick

# Install Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# Install Drush globally (matching your current version)
RUN composer global require drush/drush:^13

# Configure PHP for production (optimized for recipe operations)
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

# Set working directory (GitHub Actions will deploy code here)
WORKDIR /var/www/html

# Create necessary directories with correct permissions
RUN mkdir -p /var/www/html/web/sites/default/files /var/www/html/private \
    && chown -R www-data:www-data /var/www/html

# Configure nginx
COPY docker/nginx.conf /etc/nginx/sites-available/default

# Add startup script
COPY docker/start.sh /start.sh
RUN chmod +x /start.sh

# Expose port
EXPOSE 80

CMD ["/start.sh"]
