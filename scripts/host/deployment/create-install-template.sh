#!/bin/bash

# Decoupled Drupal Docker Installation Script
# This script installs Drupal core and applies dcloud recipes inside Docker containers
# Runs in production mode by default, use --local flag for local development

set -e  # Exit on any error

# Default to production environment unless --local flag is passed
ENVIRONMENT="prod"
VERBOSE="false"

# Parse command line arguments
for arg in "$@"; do
    case $arg in
        --local)
            ENVIRONMENT="local"
            ;;
        --verbose|-v)
            VERBOSE="true"
            ;;
        --help|-h)
            echo "Usage: $0 [--local] [--verbose|-v] [--help|-h]"
            echo "  --local    : Run in local development mode (default: production)"
            echo "  --verbose  : Enable verbose output for debugging"
            echo "  --help     : Show this help message"
            exit 0
            ;;
    esac
done

echo "=================================================="
echo "Decoupled Drupal Docker Installation Starting..."
echo "Environment: $ENVIRONMENT"
echo "=================================================="

# Set environment-specific variables
if [ "$ENVIRONMENT" = "prod" ]; then
    COMPOSE_FILE="docker-compose.prod.yml"
    SERVICE_NAME="drupal"
    CONTAINER_NAME="drupal-web"
    
    # Load environment variables from .env file for Terraform deployments.
    if [ -f ".env" ]; then
        source .env
    fi

    # DOMAIN_SUFFIX must be set in .env file
    if [ -z "$DOMAIN_SUFFIX" ]; then
        echo "Error: DOMAIN_SUFFIX is not set in .env file"
        exit 1
    fi

    SITE_URL="https://template.${DOMAIN_SUFFIX}"
    SITE_NAME="Decoupled Drupal Production"
    ADMIN_EMAIL="admin@template.${DOMAIN_SUFFIX}"
    SITE_EMAIL="noreply@template.${DOMAIN_SUFFIX}"
else
    COMPOSE_FILE="docker-compose.local.yml"
    SERVICE_NAME="drupal"
    CONTAINER_NAME="drupal-web-local"
    SITE_URL="http://template.localhost:8888"
    SITE_NAME="Decoupled Drupal Local"
    ADMIN_EMAIL="admin@template.localhost"
    SITE_EMAIL="noreply@template.localhost"
fi

echo "Using configuration:"
echo "- Compose file: $COMPOSE_FILE"
echo "- Container: $CONTAINER_NAME"
echo "- Site URL: $SITE_URL"

# Check if Docker services are running
echo "Checking Docker services..."
if ! docker compose -f "$COMPOSE_FILE" ps "$SERVICE_NAME" | grep -q "Up"; then
    echo "Error: Drupal container is not running. Please start Docker services first:"
    echo "docker compose -f $COMPOSE_FILE up -d"
    exit 1
fi

# Wait for database to be ready
echo "Waiting for database to be ready..."
sleep 10

# Check if template site already exists
if docker compose -f "$COMPOSE_FILE" exec "$SERVICE_NAME" test -f /var/www/html/web/sites/template/settings.php; then
    echo "Template site already exists. Skipping installation..."
    echo "To reinstall, first remove the template site:"
    echo "  docker compose -f $COMPOSE_FILE exec $SERVICE_NAME rm -rf /var/www/html/web/sites/template"
    echo "  docker compose -f $COMPOSE_FILE exec $SERVICE_NAME /var/www/html/vendor/bin/drush sql:drop --uri=$SITE_URL --yes"
    SKIP_INSTALL=true
else
    SKIP_INSTALL=false

    # Create template multisite directory structure
    echo "Creating template multisite directory..."
    docker compose -f "$COMPOSE_FILE" exec "$SERVICE_NAME" mkdir -p /var/www/html/web/sites/template
    # DON'T copy settings.php yet - let drush create it during site-install.
    # Copying default.settings.php here causes Drupal to try to use it before it's configured,
    # which breaks the stream wrapper initialization for public:// during multisite installation.
    docker compose -f "$COMPOSE_FILE" exec "$SERVICE_NAME" mkdir -p /var/www/html/web/sites/template/files
    # Don't pre-create media-icons - let Drupal's media module create it during installation.
    docker compose -f "$COMPOSE_FILE" exec "$SERVICE_NAME" chmod -R 775 /var/www/html/web/sites/template/files
    docker compose -f "$COMPOSE_FILE" exec "$SERVICE_NAME" chown -R www-data:www-data /var/www/html/web/sites/template

    # Install Drupal core to template multisite
    echo "Installing Drupal core to template site..."

    # Set database credentials based on environment
    if [ "$ENVIRONMENT" = "local" ]; then
        DB_PASSWORD="${MYSQL_PASSWORD:-drupalpass}"
        DB_HOST="mysql-local"
    else
        # For Terraform deployments, passwords are in .env file (already sourced above).
        DB_PASSWORD="${MYSQL_PASSWORD}"
        DB_HOST="mysql"
        
        if [ -z "$DB_PASSWORD" ]; then
            echo "Error: MYSQL_PASSWORD not set in .env file"
            exit 1
        fi
    fi

    # Generate a secure random password for admin account.
    ADMIN_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-20)
    
    docker compose -f "$COMPOSE_FILE" exec -T -e MYSQL_PASSWORD="$DB_PASSWORD" "$SERVICE_NAME" /var/www/html/vendor/bin/drush site:install dc_core \
        --uri="$SITE_URL" \
        --sites-subdir=template \
        --db-url="mysql://drupal:${DB_PASSWORD}@${DB_HOST}:3306/template" \
        --site-name="$SITE_NAME" \
        --account-name=admin \
        --account-pass="$ADMIN_PASSWORD" \
        --account-mail="$ADMIN_EMAIL" \
        --site-mail="$SITE_EMAIL" \
        --yes

    # Save admin password to file for reference.
    echo "$ADMIN_PASSWORD" > /root/.template-admin-password
    chmod 600 /root/.template-admin-password
    
    echo "Drupal installation with dc_core profile complete!"
    echo "Admin password saved to: /root/.template-admin-password"

    # Configure trusted_host_patterns for security
    echo "Configuring trusted host patterns for security..."
    if [ "$ENVIRONMENT" = "local" ]; then
        TRUSTED_HOST_PATTERN="^.+\\\\.localhost\\\$"
    else
        # Escape dots in domain suffix for regex
        ESCAPED_DOMAIN=$(echo "$DOMAIN_SUFFIX" | sed 's/\./\\\\./g')
        TRUSTED_HOST_PATTERN="^.+\\\\.${ESCAPED_DOMAIN}\\\$"
    fi

    # Make settings.php writable, append trusted_host_patterns, then make it read-only again
    docker compose -f "$COMPOSE_FILE" exec "$SERVICE_NAME" chmod 644 /var/www/html/web/sites/template/settings.php
    docker compose -f "$COMPOSE_FILE" exec "$SERVICE_NAME" bash -c "echo '
// Trusted host patterns for security
\$settings['\''trusted_host_patterns'\''] = [
  '\''${TRUSTED_HOST_PATTERN}'\'',
];' >> /var/www/html/web/sites/template/settings.php"
    docker compose -f "$COMPOSE_FILE" exec "$SERVICE_NAME" chmod 444 /var/www/html/web/sites/template/settings.php
    echo "Trusted host patterns configured."
fi

# Add template site to sites.php for multisite routing
echo "Adding template site to sites.php..."
if [ "$ENVIRONMENT" = "local" ]; then
    docker compose -f "$COMPOSE_FILE" exec "$SERVICE_NAME" bash -c 'echo "\$sites[\"8888.template.localhost\"] = \"template\";" >> /var/www/html/web/sites/sites.php'
else
    # Use DOMAIN_SUFFIX from environment for Terraform deployments.
    docker compose -f "$COMPOSE_FILE" exec "$SERVICE_NAME" bash -c "echo \"\\\$sites['template.${DOMAIN_SUFFIX}'] = 'template';\" >> /var/www/html/web/sites/sites.php"
fi
echo "Template site added to sites.php"

# The dc_core install profile handles all setup automatically.
# No need to apply recipes separately.

# Clear caches
echo "Clearing caches..."
docker compose -f "$COMPOSE_FILE" exec "$SERVICE_NAME" /var/www/html/vendor/bin/drush cache:rebuild --uri="$SITE_URL"

# Fix template directory permissions to allow OAuth key generation
# Drupal sets sites/template to read-only after installation, preventing the
# OAuth key generator from creating the private directory
echo "Fixing template directory permissions for OAuth setup..."
docker compose -f "$COMPOSE_FILE" exec "$SERVICE_NAME" chmod -R 755 /var/www/html/web/sites/template
docker compose -f "$COMPOSE_FILE" exec "$SERVICE_NAME" chown -R www-data:www-data /var/www/html/web/sites/template

# Check if consumers-next script exists and run it
echo "Setting up OAuth consumers..."
if docker compose -f "$COMPOSE_FILE" exec "$SERVICE_NAME" test -f /var/www/html/scripts/container/consumers-next.php; then
    docker compose -f "$COMPOSE_FILE" exec "$SERVICE_NAME" /var/www/html/vendor/bin/drush scr --uri="$SITE_URL" scripts/container/consumers-next.php
    echo "OAuth consumers configured!"
else
    echo "Warning: consumers-next.php script not found, skipping OAuth setup"
fi

# Set homepage to dcloud configuration page
echo "Setting homepage to /dc-config..."
docker compose -f "$COMPOSE_FILE" exec "$SERVICE_NAME" /var/www/html/vendor/bin/drush config:set --uri="$SITE_URL" system.site page.front /dc-config --yes

# Final cache rebuild to ensure everything is fresh
echo "Final cache rebuild..."
docker compose -f "$COMPOSE_FILE" exec "$SERVICE_NAME" /var/www/html/vendor/bin/drush cache:rebuild --uri="$SITE_URL"

# Generate login link
echo "Generating admin login link..."
LOGIN_URL=$(docker compose -f "$COMPOSE_FILE" exec "$SERVICE_NAME" /var/www/html/vendor/bin/drush user:login --uri="$SITE_URL" | tr -d '\r')

echo "=================================================="
echo "✅ Decoupled Drupal installation completed successfully!"
echo "Template site installed successfully"
echo "=================================================="
echo ""
echo "🌐 Site URL: $SITE_URL"
echo "👤 Admin login: $LOGIN_URL"
if [ -f "/root/.template-admin-password" ]; then
    SAVED_PASSWORD=$(cat /root/.template-admin-password)
    echo "📋 Admin credentials: admin / $SAVED_PASSWORD"
    echo "🔐 Password saved at: /root/.template-admin-password"
else
    echo "📋 Admin username: admin"
    echo "⚠️  Password not found - use 'drush uli' to generate login link"
fi
echo ""
echo "🔧 Available APIs:"
echo "   - GraphQL: $SITE_URL/graphql"
echo "   - JSON:API: $SITE_URL/jsonapi"
echo ""
echo "Happy Drupaling! 🚀"
