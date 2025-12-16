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
    DOMAIN_SUFFIX=${DOMAIN_SUFFIX:-"dcloud.dev"}
    SITE_URL="https://template.${DOMAIN_SUFFIX}"
    SITE_NAME="Drupal Cloud Production"
    ADMIN_EMAIL="admin@template.${DOMAIN_SUFFIX}"
    SITE_EMAIL="noreply@template.${DOMAIN_SUFFIX}"
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
    docker compose -f "$COMPOSE_FILE" exec "$SERVICE_NAME" cp /var/www/html/web/sites/default/default.settings.php \
        /var/www/html/web/sites/template/settings.php
    docker compose -f "$COMPOSE_FILE" exec "$SERVICE_NAME" mkdir -p /var/www/html/web/sites/template/files
    docker compose -f "$COMPOSE_FILE" exec "$SERVICE_NAME" chown -R www-data:www-data /var/www/html/web/sites/template

    # Install Drupal core to template multisite
    echo "Installing Drupal core to template site..."
    docker compose -f "$COMPOSE_FILE" exec "$SERVICE_NAME" /var/www/html/vendor/bin/drush site-install minimal \
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
fi

# Create sites.php for multisite routing
echo "Creating sites.php with template site configuration..."
if [ "$ENVIRONMENT" = "local" ]; then
    docker compose -f "$COMPOSE_FILE" exec "$SERVICE_NAME" bash -c 'cat > /var/www/html/web/sites/sites.php << '\''EOF'\''
<?php

/**
 * @file
 * Configuration file for multi-site support and directory aliasing feature.
 */

\$sites["8888.template.localhost"] = "template";
EOF
'
else
    docker compose -f "$COMPOSE_FILE" exec "$SERVICE_NAME" bash -c "cat > /var/www/html/web/sites/sites.php << 'EOF'
<?php

/**
 * @file
 * Configuration file for multi-site support and directory aliasing feature.
 */

\$sites[\"template.${DOMAIN_SUFFIX}\"] = \"template\";
EOF
"
fi
echo "sites.php created successfully"

# Copy recipes and custom modules to container (only for local - prod should have them in volume)
if [ "$ENVIRONMENT" = "local" ]; then
    echo "Copying recipes to container..."
    docker compose -f "$COMPOSE_FILE" cp ../dcloud/recipes "$SERVICE_NAME":/var/www/html/
    echo "Recipes copied successfully!"
    
    echo "Copying custom dcloud modules..."
    docker compose -f "$COMPOSE_FILE" exec "$SERVICE_NAME" mkdir -p /var/www/html/web/modules/custom
    docker compose -f "$COMPOSE_FILE" cp ../dcloud/web/modules/custom "$SERVICE_NAME":/var/www/html/web/modules/
    echo "Custom modules copied successfully!"
else
    echo "Production mode: assuming recipes and modules are already available in volume"
fi

# Function to apply recipe using core PHP recipe script
apply_recipe() {
    local recipe_name="$1"
    echo "Applying $recipe_name recipe..."

    # Apply the recipe using the core PHP recipe script
    # Note: Recipe script must be run from web directory and uses the multisite URI from environment
    if docker compose -f "$COMPOSE_FILE" exec "$SERVICE_NAME" bash -c "cd /var/www/html/web && export DRUPAL_MULTISITE_URI=$SITE_URL && php core/scripts/drupal recipe /var/www/html/recipes/$recipe_name"; then
        echo "✅ $recipe_name recipe applied successfully!"

        # For dc-admin, set Gin as default theme (in addition to admin)
        if [ "$recipe_name" = "dc-admin" ]; then
            echo "Setting Gin as default theme..."
            docker compose -f "$COMPOSE_FILE" exec "$SERVICE_NAME" /var/www/html/vendor/bin/drush config:set --uri="$SITE_URL" system.theme default gin --yes
        fi

        # For dc-core, enable custom dcloud modules
        if [ "$recipe_name" = "dc-core" ]; then
            echo "Enabling custom dcloud modules..."
            docker compose -f "$COMPOSE_FILE" exec "$SERVICE_NAME" /var/www/html/vendor/bin/drush pm:enable --uri="$SITE_URL" --yes \
                dc_chatbot dc_config dc_import dc_revalidate dc_usage dc_user_redirect
        fi

        return 0
    else
        echo "❌ Failed to apply $recipe_name recipe"
        return 1
    fi
}

# Only apply recipes if we did a fresh installation
if [ "$SKIP_INSTALL" = false ]; then
    # Apply recipes in correct dependency order:
    # 1. dc-core: Provides base Drupal functionality (node, taxonomy, etc.)
    # 2. dc-fields: Adds custom fields
    # 3. dc-api: GraphQL and API functionality
    # 4. dc-admin: Admin theme and UI (depends on node from dc-core)
    # 5. dc-content: Content types (depends on fields and core)

    if ! apply_recipe "dc-core"; then
        echo "Error: Failed to apply dc-core recipe"
        exit 1
    fi

    if ! apply_recipe "dc-fields"; then
        echo "Error: Failed to apply dc-fields recipe"
        exit 1
    fi

    if ! apply_recipe "dc-api"; then
        echo "Error: Failed to apply dc-api recipe"
        exit 1
    fi

    if ! apply_recipe "dc-admin"; then
        echo "Error: Failed to apply dc-admin recipe"
        exit 1
    fi

    if ! apply_recipe "dc-content"; then
        echo "Error: Failed to apply dc-content recipe"
        exit 1
    fi
else
    echo "Skipping recipe application since template already exists."
fi

# Clear caches
echo "Clearing caches..."
docker compose -f "$COMPOSE_FILE" exec "$SERVICE_NAME" /var/www/html/vendor/bin/drush cache:rebuild --uri="$SITE_URL"

# Check if consumers-next script exists and run it
echo "Setting up OAuth consumers..."
if docker compose -f "$COMPOSE_FILE" exec "$SERVICE_NAME" test -f /var/www/html/scripts/container/consumers-next.php; then
    docker compose -f "$COMPOSE_FILE" exec "$SERVICE_NAME" /var/www/html/vendor/bin/drush scr --uri="$SITE_URL" scripts/container/consumers-next.php
    echo "OAuth consumers configured!"
else
    echo "Warning: consumers-next.php script not found, skipping OAuth setup"
fi

# Set homepage to dcloud configuration page
echo "Setting homepage to dcloud configuration page..."
docker compose -f "$COMPOSE_FILE" exec "$SERVICE_NAME" /var/www/html/vendor/bin/drush config:set --uri="$SITE_URL" system.site page.front /dc-config --yes

# Final cache rebuild to ensure everything is fresh
echo "Final cache rebuild..."
docker compose -f "$COMPOSE_FILE" exec "$SERVICE_NAME" /var/www/html/vendor/bin/drush cache:rebuild --uri="$SITE_URL"

# Generate login link
echo "Generating admin login link..."
LOGIN_URL=$(docker compose -f "$COMPOSE_FILE" exec "$SERVICE_NAME" /var/www/html/vendor/bin/drush user:login --uri="$SITE_URL" | tr -d '\r')

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
