# Drupal Cloud Docker Template

This is the Docker-based Drupal 11 multisite backend template for the Drupal Cloud project. It provides a headless CMS with GraphQL API, OAuth authentication, and multisite capabilities for creating and managing individual Drupal sites using Docker containers.

## Overview

This template serves as the Docker-based backend for the Drupal Cloud dashboard, enabling:

- **Docker-based Deployment**: Containerized Drupal environment for production and local development
- **Multisite Architecture**: Each "space" gets its own Drupal site with separate database
- **GraphQL API**: Headless CMS capabilities with GraphQL Compose
- **OAuth Integration**: Simple OAuth for secure API authentication
- **MariaDB Database**: Production-ready MySQL/MariaDB 11.4 for all sites

## Key Features

- **Drupal 11**: Latest Drupal version with modern PHP 8.3
- **Docker Compose**: Multi-container orchestration for drupal, mysql, and nginx-proxy
- **GraphQL Compose**: Automatic GraphQL schema generation
- **Simple OAuth**: API authentication for headless applications
- **Admin Toolbar**: Enhanced admin experience with Gin theme
- **Paragraphs**: Flexible content modeling
- **Pathauto**: Automatic URL alias generation
- **Multisite Ready**: Configured for wildcard subdomain support via nginx-proxy
- **Custom Modules**: Enhanced functionality with dcloud-specific modules
- **MariaDB 11.4**: Robust database with auto-upgrade support
- **Usage Tracking**: Built-in API request and content usage monitoring
- **Drupal Recipes**: Modular installation system with dcloud recipes

## Architecture

```
├── docker/                  # Docker configuration files
│   ├── nginx.conf           # Custom nginx configuration
│   └── mysql-init.sql       # Database initialization
├── web/                     # Drupal web root
│   ├── sites/               # Multisite configurations
│   │   ├── default/         # Default site
│   │   └── sites.php        # Multisite routing
│   ├── modules/custom/      # Custom modules
│   │   ├── dcloud_chatbot/  # AI-powered content generation
│   │   ├── dcloud_config/   # Space configuration
│   │   ├── dcloud_import/   # Content import/export
│   │   ├── dcloud_revalidate/ # Next.js revalidation
│   │   ├── dcloud_usage/    # Usage statistics
│   │   └── dcloud_user_redirect/ # Authentication
│   ├── themes/custom/       # Custom themes
│   └── recipes/             # Drupal recipes
│       ├── dcloud-admin/    # Admin interface setup
│       ├── dcloud-api/      # GraphQL & OAuth setup
│       ├── dcloud-fields/   # Field configurations
│       ├── dcloud-core/     # Core functionality
│       └── dcloud-content/  # Sample content
├── config/                  # Configuration management
├── scripts/                 # Deployment and utility scripts
│   ├── clone-drupal-site.sh # Clone sites for new spaces
│   ├── delete-drupal-site.sh # Remove sites
│   ├── get-site-status.sh   # Site health checks
│   ├── backup-site.sh       # Backup functionality
│   └── list-sites.sh        # List all sites
├── docker-compose.local.yml # Local development configuration
├── docker-compose.prod.yml  # Production configuration
├── Dockerfile               # Custom Drupal PHP-FPM image
├── create-install-template.sh # Template installation script
└── composer.json            # Dependencies and project metadata
```

## Quick Start

### Prerequisites

- **Docker Desktop** or **Docker Engine** installed
- **Docker Compose** v2.0+
- **Git** for cloning repositories
- At least 4GB RAM available for Docker

### Local Development Setup

#### Step 1: Initial Setup

The `dcloud-docker` template needs the Drupal codebase from the `dcloud` template. This is a one-time setup:

```bash
# Navigate to the templates directory
cd /path/to/drupalcloud/templates

# Copy Drupal codebase from dcloud to dcloud-docker
# (Exclude DDEV-specific files and generated directories)
rsync -av --exclude='.ddev' --exclude='vendor' --exclude='web/sites/default/files' \
  dcloud/ dcloud-docker/
```

#### Step 2: Start Docker Containers

```bash
cd dcloud-docker

# Start the containers
docker-compose -f docker-compose.local.yml up -d

# Verify containers are running
docker-compose -f docker-compose.local.yml ps
```

You should see three containers:
- `drupal-web-local` - PHP-FPM application server
- `mysql-local` - MariaDB 11.4 database
- `nginx-proxy-local` - Nginx reverse proxy

#### Step 3: Install Composer Dependencies

```bash
# Install Composer dependencies inside the container
docker exec drupal-web-local composer install --no-interaction
```

#### Step 4: Create Template Site

```bash
# Run the installation script for local environment
./create-install-template.sh --local
```

This script will:
1. Create template multisite directory structure (`/web/sites/template`)
2. Install Drupal 11 core to the template site with separate database
3. Apply all 5 dcloud recipes in order:
   - `dcloud-admin` - Admin interface with Gin theme
   - `dcloud-api` - GraphQL & OAuth configuration
   - `dcloud-fields` - Custom field configurations
   - `dcloud-core` - Core multisite functionality
   - `dcloud-content` - Sample content types
4. Configure OAuth consumers for Next.js
5. Generate admin login credentials
6. Set up GraphQL and JSON:API endpoints

**Note**: The script installs to `/web/sites/template` (not `/web/sites/default`) with its own `template` database. This ensures the clone scripts can properly find and duplicate the template site.

#### Step 5: Access Your Site

After installation completes:

- **Template Site**: http://template.localhost:8888
- **Admin Login**: Use the one-time login link provided in the installation output
- **Default Credentials**: admin/admin
- **GraphQL Explorer**: http://template.localhost:8888/graphql/explorer
- **JSON:API**: http://template.localhost:8888/jsonapi

### Environment-Specific Configuration

#### Local Development (docker-compose.local.yml)

```yaml
Environment: local
Container: drupal-web-local
Site URL: http://template.localhost:8888
Domain Suffix: localhost
Database: mysql-local (MariaDB 11.4)
Port Mapping: 8888:80 (HTTP)
```

#### Production (docker-compose.prod.yml)

```yaml
Environment: prod
Container: drupal-web
Site URL: https://template.decoupled.io
Domain Suffix: decoupled.io
Database: mysql (MariaDB 11.4)
Port Mapping: 80:80 (HTTP), 443:443 (HTTPS)
SSL: Let's Encrypt via nginx-proxy
```

## Key Dependencies

### Core Drupal Modules
- **drupal/core-recommended**: Drupal 11.2+ core
- **drupal/admin_toolbar**: Enhanced admin interface
- **drupal/gin**: Modern admin theme
- **drupal/gin_login**: Styled login pages

### Headless/API Modules
- **drupal/graphql**: GraphQL API foundation
- **drupal/graphql_compose**: Automatic schema generation
- **drupal/simple_oauth**: OAuth 2.0 authentication
- **drupal/decoupled_preview_iframe**: Preview support for headless

### Content Management
- **drupal/paragraphs**: Flexible content components
- **drupal/field_group**: Organize form fields
- **drupal/pathauto**: Automatic URL aliases

### Custom Modules
- **dcloud_chatbot**: AI-powered content generation and assistance
- **dcloud_config**: Space configuration and setup wizards
- **dcloud_import**: Content import/export functionality
- **dcloud_revalidate**: Next.js revalidation integration
- **dcloud_usage**: Usage statistics and API request tracking
- **dcloud_user_redirect**: User authentication and redirection

### Development Tools
- **drush/drush**: Command-line interface (v13.x)
- **cweagans/composer-patches**: Apply patches via Composer

## Docker Configuration

### Container Services

#### 1. Drupal (PHP-FPM)
- **Image**: Custom built from `Dockerfile`
- **Base**: `php:8.3-fpm`
- **Port**: 9000 (internal), 8888 (external for local)
- **Volume Mounts**:
  - `.:/var/www/html` - Application code
  - `drupal_files:/var/www/html/web/sites/default/files` - Uploaded files
  - `drupal_private:/var/www/html/private` - Private files

#### 2. MySQL (MariaDB)
- **Image**: `mariadb:11.4`
- **Port**: 3306 (internal only)
- **Credentials** (local):
  - Root: `rootpass`
  - Database: `drupal`
  - User: `drupal`
  - Password: `drupalpass`
- **Features**: Auto-upgrade enabled
- **Volume**: `mysql_data:/var/lib/mysql`

#### 3. Nginx Proxy
- **Image**: `nginxproxy/nginx-proxy`
- **Port**: 8000:80 (local)
- **Purpose**: Routes wildcard subdomains to containers
- **Configuration**: Reads `VIRTUAL_HOST` environment variable

### Volume Management

```bash
# List Docker volumes
docker volume ls

# Inspect a volume
docker volume inspect dcloud-docker_mysql_data

# Backup database volume
docker run --rm -v dcloud-docker_mysql_data:/data -v $(pwd):/backup \
  ubuntu tar czf /backup/mysql-backup.tar.gz /data

# Restore database volume
docker run --rm -v dcloud-docker_mysql_data:/data -v $(pwd):/backup \
  ubuntu tar xzf /backup/mysql-backup.tar.gz -C /data --strip 1
```

## Multisite Management

### Creating New Sites

Sites are created automatically by the Drupal Cloud dashboard using the `clone-drupal-site.sh` script:

```bash
# Manual site creation (for testing)
docker exec drupal-web-local /var/www/html/scripts/clone-drupal-site.sh \
  <machine_name> \
  <space_auth_token> \
  template \
  <chatbot_api_key>
```

### Site Management Scripts

All scripts are located in `/scripts/` and are accessible inside the container:

#### clone-drupal-site.sh
Clones the template site to create a new space:
- Creates new database
- Clones database from template
- Configures multisite settings
- Sets up OAuth consumers
- Configures usage tracking

#### delete-drupal-site.sh
Removes a space and its database:
```bash
docker exec drupal-web-local /var/www/html/scripts/delete-drupal-site.sh <machine_name>
```

#### get-site-status.sh
Checks the status of a specific site:
```bash
docker exec drupal-web-local /var/www/html/scripts/get-site-status.sh <machine_name>
```

#### list-sites.sh
Lists all active sites:
```bash
docker exec drupal-web-local /var/www/html/scripts/list-sites.sh
```

#### backup-site.sh
Creates backups of site database and files:
```bash
docker exec drupal-web-local /var/www/html/scripts/backup-site.sh <machine_name>
```

### Accessing Sites

Each space gets its own subdomain:

- **Local**: `http://<machine_name>.localhost:8888`
- **Production**: `https://<machine_name>.decoupled.io`

The nginx-proxy container automatically routes requests based on the `Host` header.

## GraphQL API

### Endpoints

- **GraphQL API**: `/graphql`
- **GraphQL Explorer**: `/graphql/explorer` (interactive IDE)
- **Schema**: Auto-generated from content types

### Example Query

```graphql
query {
  nodeArticles(first: 10) {
    nodes {
      title
      body {
        processed
      }
      author {
        displayName
      }
    }
  }
}
```

### Authentication

GraphQL requests require OAuth 2.0 Bearer tokens:

```bash
# Get OAuth token
curl -X POST http://template.localhost:8888/oauth/token \
  -d "grant_type=client_credentials" \
  -d "client_id=YOUR_CLIENT_ID" \
  -d "client_secret=YOUR_CLIENT_SECRET"

# Use token in GraphQL request
curl -X POST http://template.localhost:8888/graphql \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"query": "{ nodeArticles { nodes { title } } }"}'
```

## OAuth Configuration

OAuth consumers are created automatically during template installation. The credentials are displayed in the installation output:

```
--- Next.js Frontend (Previewer) ---
DRUPAL_CLIENT_ID=<generated-id>
DRUPAL_CLIENT_SECRET=<generated-secret>

--- Next.js Viewer ---
DRUPAL_CLIENT_ID=<generated-id>
DRUPAL_CLIENT_SECRET=<generated-secret>
```

These credentials should be added to your Next.js dashboard's `.env` file.

## Development Workflow

### Starting/Stopping Containers

```bash
# Start containers
docker-compose -f docker-compose.local.yml up -d

# Stop containers
docker-compose -f docker-compose.local.yml down

# Stop and remove volumes (WARNING: deletes all data)
docker-compose -f docker-compose.local.yml down -v

# Restart containers
docker-compose -f docker-compose.local.yml restart

# View logs
docker-compose -f docker-compose.local.yml logs -f drupal

# View all logs
docker-compose -f docker-compose.local.yml logs -f
```

### Accessing Containers

```bash
# Access Drupal container shell
docker exec -it drupal-web-local bash

# Access MySQL directly
docker exec -it mysql-local mysql -u drupal -p drupal

# Run Drush commands
docker exec drupal-web-local vendor/bin/drush status

# Clear Drupal cache
docker exec drupal-web-local vendor/bin/drush cache:rebuild

# Export configuration
docker exec drupal-web-local vendor/bin/drush config:export

# Import configuration
docker exec drupal-web-local vendor/bin/drush config:import
```

### Database Management

```bash
# Export database
docker exec mysql-local mysqldump -u drupal -pdrupalpass drupal > backup.sql

# Import database
docker exec -i mysql-local mysql -u drupal -pdrupalpass drupal < backup.sql

# Access MySQL shell
docker exec -it mysql-local mysql -u root -prootpass

# List all databases
docker exec mysql-local mysql -u root -prootpass -e "SHOW DATABASES;"
```

### Composer Operations

```bash
# Install new package
docker exec drupal-web-local composer require drupal/module_name

# Update packages
docker exec drupal-web-local composer update

# Remove package
docker exec drupal-web-local composer remove drupal/module_name

# Clear composer cache
docker exec drupal-web-local composer clear-cache
```

## Drupal Recipes

The template uses Drupal's recipe system for modular installation. All recipes are in `/web/recipes/`:

### 1. dcloud-admin
Sets up admin interface with Gin theme:
- Installs Gin admin theme and Gin Login
- Configures admin toolbar
- Sets default admin theme

### 2. dcloud-api
Configures headless API functionality:
- Installs GraphQL and GraphQL Compose
- Installs Simple OAuth for authentication
- Configures CORS settings
- Sets up decoupled preview

### 3. dcloud-fields
Adds custom field configurations:
- Creates reusable field configurations
- Sets up paragraph types
- Configures field groups

### 4. dcloud-core
Core multisite functionality:
- Enables all custom dcloud modules
- Configures site settings
- Sets up usage tracking
- Configures revalidation

### 5. dcloud-content
Sample content types and structure:
- Creates Article and Page content types
- Adds sample taxonomy vocabularies
- Creates initial content

### Applying Recipes Manually

```bash
# Apply a specific recipe
docker exec drupal-web-local php /var/www/html/web/core/scripts/drupal recipe \
  /var/www/html/web/recipes/dcloud-core

# Apply with Drush
docker exec drupal-web-local vendor/bin/drush recipe:apply dcloud-core
```

## Custom Module APIs

### dcloud_usage
**Endpoint**: `/api/dcloud/usage`

Real-time usage statistics including:
- API request counts
- Content statistics
- GraphQL query metrics

### dcloud_chatbot
**Endpoint**: `/api/chatbot/*`

AI-powered content assistance:
- Content generation
- SEO optimization
- Content suggestions

### dcloud_import
**Endpoint**: `/api/dcloud-import`

Content import/export:
- Bulk content import
- Export to JSON
- Migration support

### dcloud_revalidate
Integration with Next.js ISR:
- On-demand revalidation
- Cache invalidation
- Webhook support

## Troubleshooting

### Common Issues

#### Container Won't Start

```bash
# Check container logs
docker-compose -f docker-compose.local.yml logs drupal

# Check Docker daemon
docker ps -a

# Restart Docker Desktop
# macOS: Click Docker icon > Restart
# Linux: sudo systemctl restart docker
```

#### Database Connection Errors

```bash
# Verify MySQL container is running
docker-compose -f docker-compose.local.yml ps mysql

# Check database credentials in web/sites/default/settings.php
# For local: host should be "mysql" (not "localhost" or "db")
docker exec drupal-web-local cat web/sites/default/settings.php | grep database

# Test database connection
docker exec mysql-local mysql -u drupal -pdrupalpass -e "SELECT 1;"
```

#### Permission Issues

```bash
# Fix file permissions inside container
docker exec drupal-web-local chown -R www-data:www-data \
  /var/www/html/web/sites/default/files

# Fix private files permissions
docker exec drupal-web-local chown -R www-data:www-data \
  /var/www/html/private
```

#### Port Already in Use

```bash
# Check what's using port 8888
lsof -i :8888

# Kill the process or change port in docker-compose.local.yml:
# ports:
#   - "8889:80"  # Change 8888 to 8889
```

#### Missing Drush

If you get "Drush not found" errors:

```bash
# Verify Drush is installed
docker exec drupal-web-local ls -la /var/www/html/vendor/bin/drush

# If missing, install Composer dependencies
docker exec drupal-web-local composer install --no-interaction

# Verify installation
docker exec drupal-web-local vendor/bin/drush --version
```

#### Scripts Not Found

If clone/delete scripts fail:

```bash
# Verify scripts exist in container
docker exec drupal-web-local ls -la /var/www/html/scripts/

# Check script permissions
docker exec drupal-web-local chmod +x /var/www/html/scripts/*.sh

# Verify volume mount in docker-compose.local.yml
# Should be: .:/var/www/html:cached
```

#### Wrong Domain (dcloud.ddev.site instead of localhost)

If spaces are created with the wrong domain (e.g., `https://xxx.dcloud.ddev.site` instead of `http://xxx.localhost:8888`):

```bash
# 1. Update DOMAIN_SUFFIX in .env.local
# Change DOMAIN_SUFFIX="dcloud.ddev.site" to DOMAIN_SUFFIX="localhost"

# 2. Restart the dev server
npm run dev

# 3. Fix existing spaces in database (if needed)
psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
  -c "UPDATE spaces SET drupal_site_url =
      REPLACE(drupal_site_url, 'dcloud.ddev.site', 'localhost:8888')
      WHERE drupal_site_url LIKE '%dcloud.ddev.site%';"
```

This issue occurs when transitioning from DDEV to Docker setup. The `DOMAIN_SUFFIX` environment variable must match your deployment method.

#### Template Site Not Found

If you get "Source site not found: /var/www/html/web/sites/template" error when creating spaces:

```bash
# 1. Verify template directory exists in container
docker exec drupal-web-local ls -la /var/www/html/web/sites/template

# 2. If missing, re-run the installation script
cd /path/to/templates/dcloud-docker
./create-install-template.sh --local

# 3. Verify template database exists
docker exec mysql-local mysql -u root -prootpass -e "SHOW DATABASES LIKE 'template';"
```

The `create-install-template.sh` script creates the template site at `/web/sites/template` with its own database. If this directory is missing, spaces cannot be cloned.

#### Permission Denied on settings.php

If you get "Permission denied" errors when cloning spaces:

```bash
# This has been fixed in the clone-drupal-site.sh script
# The script now makes settings.php writable before updating it

# If you still encounter this issue, verify the fix is applied:
docker exec drupal-web-local grep "chmod u+w" /var/www/html/scripts/clone-drupal-site.sh

# Manual fix (if needed):
docker exec drupal-web-local chmod u+w /var/www/html/web/sites/<machine_name>/settings.php
```

The clone script automatically handles this by running `chmod u+w` on settings.php before writing to it, then setting it back to secure permissions (644) after.

### Performance Optimization

```bash
# Enable PHP OPcache (already enabled in Dockerfile)
# Verify OPcache is enabled
docker exec drupal-web-local php -i | grep opcache.enable

# Optimize Composer autoloader
docker exec drupal-web-local composer dump-autoload --optimize --no-dev

# Enable Drupal caching
docker exec drupal-web-local vendor/bin/drush pm:enable page_cache dynamic_page_cache

# Clear all caches
docker exec drupal-web-local vendor/bin/drush cache:rebuild

# Increase PHP memory limit if needed
# Edit Dockerfile and rebuild:
# RUN echo "memory_limit = 512M" > /usr/local/etc/php/conf.d/memory.ini
```

### Logs and Debugging

```bash
# View real-time logs for all containers
docker-compose -f docker-compose.local.yml logs -f

# View logs for specific container
docker-compose -f docker-compose.local.yml logs -f drupal

# View Drupal watchdog logs
docker exec drupal-web-local vendor/bin/drush watchdog:show

# View PHP error log
docker exec drupal-web-local tail -f /var/log/apache2/error.log

# Enable Drupal development mode
docker exec drupal-web-local vendor/bin/drush config:set system.performance \
  css.preprocess 0
docker exec drupal-web-local vendor/bin/drush config:set system.performance \
  js.preprocess 0
```

## Production Deployment

### Build and Push Image

```bash
# Build custom Drupal image
docker build -t drupal-cloud-backend:latest .

# Tag for registry
docker tag drupal-cloud-backend:latest your-registry.com/drupal-cloud:latest

# Push to registry
docker push your-registry.com/drupal-cloud:latest
```

### Production Environment Variables

Create a `.env` file for production:

```bash
# Database
MYSQL_ROOT_PASSWORD=<strong-password>
MYSQL_DATABASE=drupal
MYSQL_USER=drupal
MYSQL_PASSWORD=<strong-password>

# Domain
VIRTUAL_HOST=*.decoupled.io
LETSENCRYPT_HOST=*.decoupled.io
LETSENCRYPT_EMAIL=admin@decoupled.io

# PHP
PHP_MEMORY_LIMIT=512M
PHP_MAX_EXECUTION_TIME=300
```

### SSL/HTTPS Configuration

The production setup uses Let's Encrypt via nginx-proxy:

```yaml
# docker-compose.prod.yml
environment:
  - VIRTUAL_HOST=*.decoupled.io
  - LETSENCRYPT_HOST=*.decoupled.io
  - LETSENCRYPT_EMAIL=admin@decoupled.io
```

Certificates are automatically generated and renewed.

### Backup Strategy

```bash
# Automated backup script
#!/bin/bash
DATE=$(date +%Y%m%d_%H%M%S)

# Backup all databases
docker exec mysql mysqldump -u root -p$MYSQL_ROOT_PASSWORD --all-databases \
  > backups/mysql_all_$DATE.sql

# Backup files volume
docker run --rm -v dcloud-docker_drupal_files:/data -v $(pwd)/backups:/backup \
  ubuntu tar czf /backup/files_$DATE.tar.gz /data

# Backup private files
docker run --rm -v dcloud-docker_drupal_private:/data -v $(pwd)/backups:/backup \
  ubuntu tar czf /backup/private_$DATE.tar.gz /data
```

### Monitoring

```bash
# Container health
docker-compose -f docker-compose.prod.yml ps

# Resource usage
docker stats

# Database connections
docker exec mysql mysql -u root -p -e \
  "SHOW PROCESSLIST;"

# Check site status
curl -I https://template.decoupled.io
```

## Integration with Drupal Cloud Dashboard

### Space Creation Flow

1. User creates space in Next.js dashboard
2. Dashboard calls `/api/spaces/background-create` endpoint
3. Dashboard executes Docker command:
   ```bash
   docker exec drupal-web-local /var/www/html/scripts/clone-drupal-site.sh \
     <machine_name> <auth_token> template <chatbot_key>
   ```
4. Script clones template database
5. Script configures multisite for new space
6. Space becomes accessible at subdomain

### Required Environment Variables

In the main Drupal Cloud dashboard `.env.local`:

```bash
# Docker Configuration
DOMAIN_SUFFIX="localhost"  # IMPORTANT: Use "localhost" for local Docker setup
                           # Use "decoupled.io" for production

# Drupal Template Space
DRUPAL_TEMPLATE_SPACE_NAME="template"

# OAuth Credentials (from template installation output)
DRUPAL_CLIENT_ID="<from-installation>"
DRUPAL_CLIENT_SECRET="<from-installation>"
```

**IMPORTANT**: The `DOMAIN_SUFFIX` must be set correctly based on your environment:
- **Local Docker**: Use `DOMAIN_SUFFIX="localhost"` (not `dcloud.ddev.site`)
- **Production**: Use `DOMAIN_SUFFIX="decoupled.io"` or your production domain

This affects how space URLs are generated:
- Local: `http://<machine_name>.localhost:8888`
- Production: `https://<machine_name>.decoupled.io`

**Note**: If you were previously using DDEV (`dcloud.ddev.site`), you must change this to `localhost` when switching to the Docker setup, and **fully restart your dev server** (not just refresh) for the changes to take effect.

**Important**: Environment variable changes in `.env.local` require a full server restart:
```bash
# Kill the current dev server
lsof -ti:3333 | xargs kill -9

# Start fresh
npm run dev
```

Without a full restart, Next.js may use cached environment variables and create spaces with the old domain.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make changes in the Docker template
4. Test with local Docker setup
5. Submit a pull request

### Code Standards

- Follow Drupal coding standards
- Test in Docker environment before committing
- Document any new scripts or configurations
- Update README for significant changes

## Security

- Keep Drupal core and modules updated via Composer
- Use strong passwords in production `.env`
- Configure proper file permissions (www-data:www-data)
- Enable HTTPS for all production sites
- Regular security updates via `composer update`
- Secure OAuth client secrets
- Use Docker secrets for sensitive data in production

## Support

- **Documentation**: This README and main project README
- **Issues**: Report bugs in the main repository
- **Docker Help**: https://docs.docker.com/
- **Drupal Documentation**: https://www.drupal.org/docs
- **Drupal Recipes**: https://www.drupal.org/docs/extending-drupal/drupal-recipes

## License

This project is licensed under the GPL-2.0-or-later license, consistent with Drupal core.

---

## Quick Reference Commands

```bash
# Initial Setup
rsync -av --exclude='.ddev' --exclude='vendor' dcloud/ dcloud-docker/
docker-compose -f docker-compose.local.yml up -d
docker exec drupal-web-local composer install --no-interaction
./create-install-template.sh --local

# Daily Development
docker-compose -f docker-compose.local.yml up -d
docker exec drupal-web-local vendor/bin/drush cr
docker exec -it drupal-web-local bash

# Site Management
docker exec drupal-web-local /var/www/html/scripts/list-sites.sh
docker exec drupal-web-local /var/www/html/scripts/get-site-status.sh <name>
docker exec drupal-web-local /var/www/html/scripts/backup-site.sh <name>

# Debugging
docker-compose -f docker-compose.local.yml logs -f drupal
docker exec drupal-web-local vendor/bin/drush watchdog:show
docker stats

# Cleanup
docker-compose -f docker-compose.local.yml down
docker system prune -a  # WARNING: removes all unused Docker resources
```
