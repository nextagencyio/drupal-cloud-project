#!/bin/bash

# Drupal Cloud Docker Installation Script
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
echo "Drupal Cloud Docker Installation Starting..."
echo "Environment: $ENVIRONMENT"
echo "=================================================="

# Set environment-specific variables
if [ "$ENVIRONMENT" = "prod" ]; then
    COMPOSE_FILE="docker-compose.prod.yml"
    SERVICE_NAME="drupal"
    CONTAINER_NAME="drupal-web"
    SITE_URL="https://template.decoupled.io"
    SITE_NAME="Drupal Cloud Production"
    ADMIN_EMAIL="admin@template.decoupled.io"
    SITE_EMAIL="noreply@template.decoupled.io"
else
    COMPOSE_FILE="docker-compose.local.yml"
    SERVICE_NAME="drupal"
    CONTAINER_NAME="drupal-web-local"
    SITE_URL="http://template.localhost:8888"
    SITE_NAME="Drupal Cloud Local"
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

# Create template multisite directory structure
echo "Creating template multisite directory..."
docker compose -f "$COMPOSE_FILE" exec "$SERVICE_NAME" mkdir -p /var/www/html/web/sites/template
docker compose -f "$COMPOSE_FILE" exec "$SERVICE_NAME" cp /var/www/html/web/sites/default/default.settings.php \
    /var/www/html/web/sites/template/settings.php
docker compose -f "$COMPOSE_FILE" exec "$SERVICE_NAME" mkdir -p /var/www/html/web/sites/template/files
docker compose -f "$COMPOSE_FILE" exec "$SERVICE_NAME" chown -R www-data:www-data /var/www/html/web/sites/template

# Install Drupal core to template multisite
echo "Installing Drupal core to template site..."
docker compose -f "$COMPOSE_FILE" exec "$SERVICE_NAME" /var/www/html/vendor/bin/drush site-install \
    --uri="$SITE_URL" \
    --sites-subdir=template \
    --db-url=mysql://drupal:drupalpass@mysql:3306/template \
    --site-name="$SITE_NAME" \
    --account-name=admin \
    --account-pass=admin \
    --account-mail="$ADMIN_EMAIL" \
    --site-mail="$SITE_EMAIL" \
    --notify=false \
    --yes

echo "Base Drupal installation complete!"

# Copy recipes to container (only for local - prod should have them in volume)
if [ "$ENVIRONMENT" = "local" ]; then
    echo "Copying recipes to container..."
    docker compose -f "$COMPOSE_FILE" cp ../dcloud/recipes "$SERVICE_NAME":/var/www/html/
    echo "Recipes copied successfully!"
else
    echo "Production mode: assuming recipes are already available in volume"
fi

# Function to apply recipe with retry logic
apply_recipe() {
    local recipe_name="$1"
    local recipe_path="/var/www/html/recipes/$recipe_name"
    local max_attempts=3
    local attempt=1

    echo "Applying $recipe_name recipe..."

    while [ $attempt -le $max_attempts ]; do
        echo "Attempt $attempt of $max_attempts for $recipe_name..."

        # Apply recipe
        if [ "$VERBOSE" = "true" ]; then
            echo "Running: docker compose -f $COMPOSE_FILE exec $SERVICE_NAME /var/www/html/vendor/bin/drush recipe $recipe_path --yes --verbose"
            if docker compose -f "$COMPOSE_FILE" exec "$SERVICE_NAME" /var/www/html/vendor/bin/drush recipe "$recipe_path" --yes --verbose; then
                echo "✅ $recipe_name recipe applied successfully!"
                return 0
            fi
        else
            if docker compose -f "$COMPOSE_FILE" exec "$SERVICE_NAME" /var/www/html/vendor/bin/drush recipe "$recipe_path" --yes; then
                echo "✅ $recipe_name recipe applied successfully!"
                return 0
            fi
        fi

        echo "❌ Attempt $attempt failed for $recipe_name"

        if [ $attempt -lt $max_attempts ]; then
            echo "Clearing cache before retry..."
            docker compose -f "$COMPOSE_FILE" exec "$SERVICE_NAME" /var/www/html/vendor/bin/drush cache:rebuild || echo "Cache clear failed, continuing..."
            echo "Waiting 30 seconds before retry..."
            sleep 30
        fi

        attempt=$((attempt + 1))
    done

    echo "❌ Failed to apply $recipe_name recipe after $max_attempts attempts"
    return 1
}

if ! apply_recipe "dcloud-admin"; then
    echo "Error: Failed to apply dcloud-admin recipe"
    exit 1
fi

# Apply recipes in correct order with retry logic
if ! apply_recipe "dcloud-api"; then
    echo "Error: Failed to apply dcloud-api recipe"
    exit 1
fi

if ! apply_recipe "dcloud-fields"; then
    echo "Error: Failed to apply dcloud-fields recipe"
    exit 1
fi

if ! apply_recipe "dcloud-core"; then
    echo "Error: Failed to apply dcloud-core recipe"
    exit 1
fi

if ! apply_recipe "dcloud-content"; then
    echo "Error: Failed to apply dcloud-content recipe"
    exit 1
fi

# Clear caches
echo "Clearing caches..."
docker compose -f "$COMPOSE_FILE" exec "$SERVICE_NAME" /var/www/html/vendor/bin/drush cache:rebuild

# Check if consumers-next script exists and run it
echo "Setting up OAuth consumers..."
if docker compose -f "$COMPOSE_FILE" exec "$SERVICE_NAME" test -f /var/www/html/scripts/consumers-next.php; then
    docker compose -f "$COMPOSE_FILE" exec "$SERVICE_NAME" /var/www/html/vendor/bin/drush scr scripts/consumers-next.php
    echo "OAuth consumers configured!"
else
    echo "Warning: consumers-next.php script not found, skipping OAuth setup"
fi

# Generate login link
echo "Generating admin login link..."
LOGIN_URL=$(docker compose -f "$COMPOSE_FILE" exec "$SERVICE_NAME" /var/www/html/vendor/bin/drush user:login --uri="$SITE_URL")

echo "=================================================="
echo "✅ Drupal Cloud installation completed successfully!"
echo "=================================================="
echo ""
echo "🌐 Site URL: $SITE_URL"
echo "👤 Admin login: $LOGIN_URL"
echo "📋 Admin credentials: admin/admin"
echo ""
echo "🔧 Available APIs:"
echo "   - GraphQL: $SITE_URL/graphql"
echo "   - JSON:API: $SITE_URL/jsonapi"
echo ""
echo "Happy Drupaling! 🚀"
