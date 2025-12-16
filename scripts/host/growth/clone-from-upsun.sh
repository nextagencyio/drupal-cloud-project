#!/bin/bash

# DrupalCloud Clone from Growth Plan Script
# Clones a Growth (Upsun) space back to a Starter (multisite) space
# Usage: ./scripts/host/growth/clone-from-growth.sh <source-growth-project-id> <new-site-name>

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Logging functions
log() {
    echo -e "${BLUE}[CLONE]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${CYAN}[STEP]${NC} $1"
}

# Show usage
show_usage() {
    echo "Usage: $0 <source-growth-project-id> <new-site-name>"
    echo ""
    echo "Clones a Growth (Upsun) space back to a Starter (multisite) space"
    echo ""
    echo "Arguments:"
    echo "  source-growth-project-id  Upsun project ID to clone from (e.g., 'qcc2td5lygnac')"
    echo "  new-site-name             Machine name for the new Starter space (e.g., 'my-new-site')"
    echo ""
    echo "Examples:"
    echo "  $0 qcc2td5lygnac my-cloned-site"
    echo ""
    echo "Prerequisites:"
    echo "  - Upsun CLI installed and authenticated"
    echo "  - Source Growth space must exist"
    echo "  - MySQL access to drupalcloud database"
    echo "  - Space on multisite server"
    echo ""
}

# Validate prerequisites
validate_prerequisites() {
    log_step "Validating prerequisites..."

    # Check if upsun CLI is installed
    if ! command -v upsun &> /dev/null; then
        log_error "Upsun CLI not found. Install it with:"
        echo "  curl -fsSL https://raw.githubusercontent.com/platformsh/cli/main/installer.sh | bash"
        exit 1
    fi

    # Check if upsun is authenticated
    if ! upsun auth:info &> /dev/null; then
        log_error "Upsun CLI not authenticated. Run: upsun auth:login"
        exit 1
    fi

    log_success "Prerequisites validated"
}

# Check command line arguments
if [[ $# -ne 2 ]]; then
    log_error "Invalid number of arguments"
    show_usage
    exit 1
fi

SOURCE_PROJECT_ID="$1"
NEW_SITE_NAME="$2"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
EXPORT_DIR="/tmp/dcloud-clone-${NEW_SITE_NAME}-${TIMESTAMP}"

# Multisite configuration
MULTISITE_DIR="/opt/drupalcloud/sites/${NEW_SITE_NAME}"
DRUPAL_WEB_DIR="/opt/drupalcloud/web"
DB_PREFIX="${NEW_SITE_NAME}_"
MULTISITE_DOMAIN="${NEW_SITE_NAME}.test3.drupalcloud.com" # Adjust as needed

log "========================================="
log "DrupalCloud Clone from Growth"
log "========================================="
log "Source Project: $SOURCE_PROJECT_ID"
log "New Site: $NEW_SITE_NAME"
log "Timestamp: $TIMESTAMP"
log "Export directory: $EXPORT_DIR"
log "========================================="

# Validate prerequisites
validate_prerequisites

# Step 1: Verify source Growth project exists
log_step "1/6 Verifying source Growth project..."

if ! upsun project:info -p "$SOURCE_PROJECT_ID" &> /dev/null; then
    log_error "Source project not found: $SOURCE_PROJECT_ID"
    log "Make sure the project exists and you have access"
    exit 1
fi

SOURCE_URL=$(upsun environment:info -p "$SOURCE_PROJECT_ID" -e main url 2>&1 | grep -oP 'https://[^\s]+' || echo "")
log_success "Source project verified: $SOURCE_URL"

# Step 2: Export database from Upsun
log_step "2/6 Exporting database from Upsun..."

mkdir -p "$EXPORT_DIR"
DB_FILE="$EXPORT_DIR/database.sql"

# Export database using drush via SSH
log "Running database export on Upsun..."
upsun ssh -p "$SOURCE_PROJECT_ID" -e main "cd web && ../vendor/bin/drush sql:dump" > "$DB_FILE"

if [[ ! -f "$DB_FILE" ]] || [[ ! -s "$DB_FILE" ]]; then
    log_error "Database export failed or is empty"
    exit 1
fi

DB_SIZE=$(du -h "$DB_FILE" | cut -f1)
log_success "Database exported ($DB_SIZE)"

# Step 3: Export files from Upsun
log_step "3/6 Exporting files from Upsun..."

FILES_DIR="$EXPORT_DIR/files"
mkdir -p "$FILES_DIR"

# Download files from Upsun mount
log "Downloading files from Upsun..."
upsun mount:download -p "$SOURCE_PROJECT_ID" -e main \
    --mount="web/sites/default/files" \
    --target="$FILES_DIR" \
    --no-interaction || log_warning "Files download failed or no files exist"

if [[ -d "$FILES_DIR" ]] && [[ "$(ls -A $FILES_DIR)" ]]; then
    FILES_COUNT=$(find "$FILES_DIR" -type f | wc -l)
    FILES_SIZE=$(du -sh "$FILES_DIR" | cut -f1)
    log_success "Files downloaded ($FILES_COUNT files, $FILES_SIZE)"
else
    log_warning "No files found to download"
fi

# Step 4: Create new Starter space in multisite
log_step "4/6 Creating new Starter space in multisite..."

# Create site directory
if [[ -d "$MULTISITE_DIR" ]]; then
    log_error "Site directory already exists: $MULTISITE_DIR"
    log "Please choose a different site name or remove the existing site"
    exit 1
fi

mkdir -p "$MULTISITE_DIR/files"
log "Site directory created: $MULTISITE_DIR"

# Create sites.php entry if needed
SITES_PHP="/opt/drupalcloud/web/sites/sites.php"
if ! grep -q "$MULTISITE_DOMAIN" "$SITES_PHP" 2>/dev/null; then
    echo "\$sites['$MULTISITE_DOMAIN'] = '$NEW_SITE_NAME';" >> "$SITES_PHP"
    log "Added multisite entry to sites.php"
fi

# Create settings.php for the new site
cat > "$MULTISITE_DIR/settings.php" << 'SETTINGS_EOF'
<?php
$databases['default']['default'] = [
  'database' => getenv('DB_NAME'),
  'username' => getenv('DB_USER'),
  'password' => getenv('DB_PASSWORD'),
  'host' => getenv('DB_HOST'),
  'port' => getenv('DB_PORT') ?: 3306,
  'driver' => 'mysql',
  'prefix' => getenv('DB_PREFIX'),
  'collation' => 'utf8mb4_general_ci',
];

$settings['hash_salt'] = getenv('DRUPAL_HASH_SALT');
$settings['config_sync_directory'] = '../config/sync';
$settings['file_private_path'] = '../private';
$settings['trusted_host_patterns'] = ['^.*$'];
SETTINGS_EOF

log_success "Settings file created"

# Step 5: Import database to multisite
log_step "5/6 Importing database to multisite..."

# Use drush to import (it will use the correct database prefix)
cd "$DRUPAL_WEB_DIR"

# First, create the site-specific alias or use URI
log "Importing database via drush..."
../vendor/bin/drush --uri="$MULTISITE_DOMAIN" sql:cli < "$DB_FILE"

# Update site-specific settings (base URL, file paths, etc.)
log "Updating site configuration for multisite..."
../vendor/bin/drush --uri="$MULTISITE_DOMAIN" config:set system.site page.front /node -y || true
../vendor/bin/drush --uri="$MULTISITE_DOMAIN" cache:rebuild || true

log_success "Database imported"

# Step 6: Import files to multisite
log_step "6/6 Importing files to multisite..."

if [[ -d "$FILES_DIR" ]] && [[ "$(ls -A $FILES_DIR)" ]]; then
    # Copy files from export to multisite
    cp -r "$FILES_DIR"/* "$MULTISITE_DIR/files/" 2>/dev/null || log_warning "No files to copy"

    # Fix permissions
    chown -R www-data:www-data "$MULTISITE_DIR/files" 2>/dev/null || \
        chown -R $(whoami):$(whoami) "$MULTISITE_DIR/files"

    log_success "Files imported"
else
    log_warning "No files to import"
fi

# Fix overall directory permissions
chown -R www-data:www-data "$MULTISITE_DIR" 2>/dev/null || \
    chown -R $(whoami):$(whoami) "$MULTISITE_DIR"

# Clean up export directory
log "Cleaning up temporary files..."
rm -rf "$EXPORT_DIR"

# Final verification
log_step "Verifying new site..."
cd "$DRUPAL_WEB_DIR"
../vendor/bin/drush --uri="$MULTISITE_DOMAIN" status || true

# Display summary
log "========================================="
log_success "Clone from Growth Complete!"
log "========================================="
log "Source Project: $SOURCE_PROJECT_ID"
log "New Starter Site: $NEW_SITE_NAME"
log "Multisite Domain: $MULTISITE_DOMAIN"
log "Site Directory: $MULTISITE_DIR"
log "========================================="
log ""
log "Next steps:"
log "1. Add site to database:"
log "   INSERT INTO spaces (name, machine_name, hosting_type, drupal_site_url, user_id)"
log "   VALUES ('$NEW_SITE_NAME', '$NEW_SITE_NAME', 'starter', 'https://$MULTISITE_DOMAIN', <user_id>);"
log ""
log "2. Test the site: https://$MULTISITE_DOMAIN"
log "3. Update DNS if needed"
log ""
log_warning "Note: This is a NEW Starter space. The source Growth space remains unchanged."
