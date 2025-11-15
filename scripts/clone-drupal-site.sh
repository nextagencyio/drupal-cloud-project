#!/bin/bash

# Clone Drupal Site Script
# Clones either the template site or an existing user site to create a new site

set -e

# Configuration
PROJECT_PATH="/var/www/html"
SITES_PATH="$PROJECT_PATH/web/sites"
DRUSH_PATH="$PROJECT_PATH/vendor/bin/drush"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log() {
    echo -e "${BLUE}[INFO]${NC} $1"
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

# Usage function
show_usage() {
    echo "Usage: $0 <TARGET_SITE_NAME> <TARGET_SPACE_TOKEN> [SOURCE_SITE_NAME] [ADMIN_PASSWORD]"
    echo ""
    echo "Arguments:"
    echo "  TARGET_SITE_NAME    Name for the new cloned site"
    echo "  TARGET_SPACE_TOKEN  Space token for the new site (space_tok_...)"
    echo "  SOURCE_SITE_NAME    Site to clone from (defaults to 'template')"
    echo "  ADMIN_PASSWORD      Password for the admin user (optional)"
    echo ""
    echo "Examples:"
    echo "  $0 mysite space_tok_1234567890abcdef1234567890abcdef123456 template mypassword123"
    echo "  $0 newsite space_tok_abcdef1234567890abcdef1234567890abcdef template"
    echo "  $0 copy space_tok_fedcba0987654321fedcba0987654321fedcba existing-site"
    echo ""
    echo "Environment variables:"
    echo "  DOMAIN_SUFFIX       Domain suffix (default: detected from environment)"
    exit 1
}

# Validation functions
validate_params() {
    if [[ -z "$TARGET_SITE" ]]; then
        log_error "TARGET_SITE_NAME is required"
        show_usage
    fi
    
    if [[ -z "$TARGET_TOKEN" ]]; then
        log_error "TARGET_SPACE_TOKEN is required"
        show_usage
    fi
    
    # Validate target name format (alphanumeric, underscores, hyphens only)
    if [[ ! "$TARGET_SITE" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log_error "Target site name must contain only letters, numbers, underscores, and hyphens"
        exit 1
    fi
    
    # Validate token format
    if [[ ! "$TARGET_TOKEN" =~ ^space_tok_[0-9a-fA-F]{54}$ ]]; then
        log_error "TARGET_SPACE_TOKEN format is invalid. Expected: space_tok_[54 hex chars]"
        exit 1
    fi
}

check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if we're in a container or have the right environment
    if [[ ! -f "$DRUSH_PATH" ]]; then
        log_error "Drush not found at $DRUSH_PATH"
        exit 1
    fi
    
    # Check if source site exists
    if [[ ! -d "$SOURCE_PATH" ]]; then
        log_error "Source site not found: $SOURCE_PATH"
        exit 1
    fi
    
    # Detect domain suffix from environment or .env file
    if [[ -z "$DOMAIN_SUFFIX" ]]; then
        if [[ -f "/var/www/html/.env" ]]; then
            DOMAIN_SUFFIX=$(grep "DOMAIN_SUFFIX=" /var/www/html/.env | cut -d'=' -f2 || echo "decoupled.io")
        else
            DOMAIN_SUFFIX="decoupled.io"
        fi
    fi
    
    log_success "Prerequisites check completed"
    log "Source site: $SOURCE_SITE"
    log "Target site: $TARGET_SITE"
    log "Domain suffix: $DOMAIN_SUFFIX"
}

check_conflicts() {
    log "Checking for naming conflicts..."
    
    local conflict_found=false
    
    # Check if target directory already exists
    if [[ -d "$TARGET_PATH" ]]; then
        log_error "Target site directory already exists: $TARGET_PATH"
        conflict_found=true
    fi
    
    # Check if target database already exists
    local target_db="drupal_${TARGET_SITE}"
    if mysql -h mysql -u root -prootpass -e "USE \`${target_db}\`;" 2>/dev/null; then
        log_error "Target database already exists: $target_db"
        conflict_found=true
    fi
    
    # Check if domain exists in sites.php
    local sites_php="$PROJECT_PATH/web/sites/sites.php"
    if [[ -f "$sites_php" ]] && grep -q "${TARGET_SITE}.${DOMAIN_SUFFIX}" "$sites_php"; then
        log_error "Target domain already exists in sites.php: ${TARGET_SITE}.${DOMAIN_SUFFIX}"
        conflict_found=true
    fi
    
    if [[ "$conflict_found" == true ]]; then
        log_error "Cannot proceed due to naming conflicts"
        exit 1
    fi
    
    log_success "No conflicts found"
}

clone_site_structure() {
    log "Cloning site directory structure..."
    
    # Copy the entire source site directory
    cp -r "$SOURCE_PATH" "$TARGET_PATH"
    
    if [[ ! -d "$TARGET_PATH" ]]; then
        log_error "Failed to create target site directory"
        exit 1
    fi
    
    log_success "Site directory structure cloned"
}

create_target_database() {
    log "Creating target database..."

    local source_db="drupal"
    local target_db="drupal_${TARGET_SITE}"

    # Special handling for template source
    if [[ "$SOURCE_SITE" == "template" ]]; then
        source_db="drupal"  # Template uses main drupal database
    else
        source_db="drupal_${SOURCE_SITE}"
    fi

    log "Source database: $source_db"
    log "Target database: $target_db"

    # Drop and recreate the target database to ensure clean slate
    log "Dropping existing database if present..."
    mysql -h mysql -u root -prootpass -e "DROP DATABASE IF EXISTS \`${target_db}\`;" || {
        log_error "Failed to drop target database: $target_db"
        exit 1
    }

    log "Creating fresh target database..."
    mysql -h mysql -u root -prootpass -e "CREATE DATABASE \`${target_db}\`;" || {
        log_error "Failed to create target database: $target_db"
        exit 1
    }

    # Grant permissions to drupal user on the new database
    log "Granting permissions to drupal user on $target_db..."
    mysql -h mysql -u root -prootpass -e "
        GRANT ALL PRIVILEGES ON \`${target_db}\`.* TO 'drupal'@'%';
        FLUSH PRIVILEGES;
    " || {
        log_error "Failed to grant permissions on database: $target_db"
        exit 1
    }

    # Import database from pre-made backup (fastest and most reliable method)
    log "Importing database from template backup..."

    # For template source, use the pre-made backup
    if [[ "$SOURCE_SITE" == "template" ]]; then
        local backup_file="/var/backups/template-backup.sql"

        if [[ ! -f "$backup_file" ]]; then
            log_error "Template backup file not found: $backup_file"
            log "Regenerating template backup..."
            mysqldump -h mysql -u root -prootpass --single-transaction --quick "$source_db" > "$backup_file" || {
                log_error "Failed to create template backup"
                exit 1
            }
        fi

        log "Using template backup: $backup_file"
        mysql -h mysql -u root -prootpass "$target_db" < "$backup_file" || {
            log_error "Failed to import template backup"
            exit 1
        }
    else
        # For cloning from another space, use mysqldump on-the-fly
        log "Cloning from space $source_db..."
        mysqldump -h mysql -u root -prootpass --single-transaction --quick "$source_db" | \
            mysql -h mysql -u root -prootpass "$target_db" || {
            log_error "Failed to clone database from $source_db"
            exit 1
        }
    fi

    log_success "Database created and populated: $target_db"
}

update_target_settings() {
    log "Updating target site settings..."
    
    local target_db="drupal_${TARGET_SITE}"
    local settings_file="$TARGET_PATH/settings.php"
    
    # Create new settings.php for the target site
    cat > "$settings_file" << EOF
<?php

/**
 * @file
 * Drupal site-specific configuration file for ${TARGET_SITE}.
 */

// Database configuration for MySQL
\$databases['default']['default'] = array (
  'database' => '${target_db}',
  'username' => 'drupal',
  'password' => 'drupalpass',
  'prefix' => '',
  'host' => 'mysql',
  'port' => '3306',
  'isolation_level' => 'READ COMMITTED',
  'driver' => 'mysql',
  'namespace' => 'Drupal\\\\mysql\\\\Driver\\\\Database\\\\mysql',
  'autoload' => 'core/modules/mysql/src/Driver/Database/mysql/',
);

// Configuration sync directory
\$settings['config_sync_directory'] = 'sites/${TARGET_SITE}/files/config/sync';

// File paths
\$settings['file_public_path'] = 'sites/${TARGET_SITE}/files';
\$settings['file_private_path'] = 'sites/${TARGET_SITE}/private';

// Hash salt for security (unique per site)
\$settings['hash_salt'] = '${TARGET_SITE}-' . hash('sha256', '${TARGET_SITE}.${DOMAIN_SUFFIX}');

// Trusted host patterns
\$settings['trusted_host_patterns'] = [
  '^$(echo "${TARGET_SITE}.${DOMAIN_SUFFIX}" | sed 's/\./\\\\./g')\$',
];

// Skip file system permissions hardening
\$settings['skip_permissions_hardening'] = TRUE;

// DrupalCloud space configuration
\$settings['drupalcloud_space_name'] = '${TARGET_SITE}';
\$settings['drupalcloud_space_token'] = '${TARGET_TOKEN}';

// Local development settings
if (file_exists(\$app_root . '/' . \$site_path . '/settings.local.php')) {
  include \$app_root . '/' . \$site_path . '/settings.local.php';
}
EOF

    # Set proper permissions
    chown www-data:www-data "$settings_file"
    chmod 644 "$settings_file"
    
    # Create config sync directory
    mkdir -p "$TARGET_PATH/files/config/sync"
    chown -R www-data:www-data "$TARGET_PATH/files"
    
    log_success "Settings.php updated for $TARGET_SITE"
}

update_sites_php() {
    log "Updating sites.php configuration..."

    local sites_php="$PROJECT_PATH/web/sites/sites.php"
    local target_domain="${TARGET_SITE}.${DOMAIN_SUFFIX}"

    # Create sites.php if it doesn't exist (using simple format)
    if [[ ! -f "$sites_php" ]]; then
        cat > "$sites_php" << 'EOF'
<?php

/**
 * @file
 * Configuration file for Drupal's multisite directory aliasing feature.
 */

// Site mappings
EOF
    fi

    # Check if our site is already in the file
    if grep -q "'$target_domain'" "$sites_php" || grep -q "\"$target_domain\"" "$sites_php"; then
        log_warning "Site $target_domain already exists in sites.php"
    else
        # Add the new site entry using simple syntax at the end
        cat >> "$sites_php" << EOF

// ${TARGET_SITE} site
\$sites['${target_domain}'] = '${TARGET_SITE}';
EOF
        log_success "Added $target_domain to sites.php"
    fi

    # Verify the file is valid PHP
    php -l "$sites_php" || {
        log_error "sites.php has syntax errors"
        exit 1
    }

    # Reload PHP-FPM to clear opcache so the new site mapping is immediately available
    if killall -USR2 php-fpm 2>/dev/null; then
        log "PHP-FPM reloaded to clear opcache"
    else
        log_warning "Could not reload PHP-FPM, opcache may take a moment to update"
    fi
}

set_permissions() {
    log "Setting proper permissions..."
    
    # Set ownership for the entire site
    chown -R www-data:www-data "$TARGET_PATH"
    
    # Set directory permissions
    find "$TARGET_PATH" -type d -exec chmod 755 {} \;
    
    # Set file permissions
    find "$TARGET_PATH" -type f -exec chmod 644 {} \;
    
    # Make files directory writable for uploads
    chmod 775 "$TARGET_PATH/files"
    find "$TARGET_PATH/files" -type d -exec chmod 775 {} \;
    
    # Protect settings.php
    chmod 644 "$TARGET_PATH/settings.php"
    
    log_success "Permissions set correctly"
}

clear_caches() {
    log "Clearing caches for the new site..."

    local target_uri="${TARGET_SITE}.${DOMAIN_SUFFIX}"

    cd "$PROJECT_PATH"

    # Clear caches with proper memory limit syntax
    if timeout 60 "$DRUSH_PATH" --uri="https://$target_uri" --define=memory_limit=1G cr --no-interaction; then
        log_success "Caches cleared successfully"
    else
        log_warning "Cache clearing failed, but site should still work"
    fi
}

validate_cloned_site() {
    log "Validating cloned site..."
    
    local target_uri="${TARGET_SITE}.${DOMAIN_SUFFIX}"
    local target_db="drupal_${TARGET_SITE}"
    
    cd "$PROJECT_PATH"
    
    # Test site status
    if timeout 30 "$DRUSH_PATH" --uri="https://$target_uri" --define=memory_limit=1G status --no-interaction > /dev/null 2>&1; then
        log_success "Site status check passed"
    else
        log_warning "Site status check failed, but site may still be functional"
    fi
    
    # Check database exists and has tables
    local table_count
    table_count=$(mysql -h mysql -u root -prootpass -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$target_db';" -N 2>/dev/null || echo "0")
    
    if [[ "$table_count" -gt 0 ]]; then
        log_success "Database has $table_count tables"
    else
        log_error "Database appears to be empty"
        exit 1
    fi
    
    log_success "Site validation completed"
}

set_admin_password() {
    log "Setting admin user password..."

    local target_uri="${TARGET_SITE}.${DOMAIN_SUFFIX}"

    cd "$PROJECT_PATH"

    if [[ -n "$ADMIN_PASSWORD" ]]; then
        log "Setting custom admin password (${#ADMIN_PASSWORD} characters)..."

        # Set the admin password using drush
        if timeout 30 "$DRUSH_PATH" --uri="https://$target_uri" --define=memory_limit=1G user:password admin "$ADMIN_PASSWORD" --no-interaction; then
            log_success "Admin password set successfully"
        else
            log_warning "Failed to set admin password, but site should still work with default password"
        fi
    else
        log_warning "No admin password provided, using default password"
    fi
}

create_site_metadata() {
    log "Creating site metadata..."

    cat > "$TARGET_PATH/space.json" << EOF
{
  "spaceName": "${TARGET_SITE}",
  "spaceToken": "${TARGET_TOKEN}",
  "domain": "${TARGET_SITE}.${DOMAIN_SUFFIX}",
  "sourceSpace": "${SOURCE_SITE}",
  "createdAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "clonedFrom": "${SOURCE_SITE}",
  "databaseType": "mysql"
}
EOF

    chmod 640 "$TARGET_PATH/space.json"
    chown www-data:www-data "$TARGET_PATH/space.json"

    log_success "Site metadata created"
}

# Main execution
main() {
    # Parse arguments
    TARGET_SITE="$1"
    TARGET_TOKEN="$2"
    SOURCE_SITE="${3:-template}"
    ADMIN_PASSWORD="$4"

    # Set paths
    SOURCE_PATH="$SITES_PATH/$SOURCE_SITE"
    TARGET_PATH="$SITES_PATH/$TARGET_SITE"
    
    # Validate parameters
    validate_params
    
    log "Starting site clone operation..."
    log "Source: $SOURCE_SITE -> Target: $TARGET_SITE"
    
    # Run clone process
    check_prerequisites
    check_conflicts
    clone_site_structure
    create_target_database
    update_target_settings
    update_sites_php
    set_permissions
    clear_caches
    set_admin_password
    validate_cloned_site
    create_site_metadata
    
    echo
    log_success "Site cloning completed successfully!"
    echo
    log "Clone Summary:"
    log "  Source Site: $SOURCE_SITE"
    log "  Target Site: $TARGET_SITE"
    log "  Target URL: https://${TARGET_SITE}.${DOMAIN_SUFFIX}"
    log "  Database: drupal_${TARGET_SITE}"
    log "  Site Directory: $TARGET_PATH"
    echo
    log_success "Your new site is ready at: https://${TARGET_SITE}.${DOMAIN_SUFFIX}"
}

# Show usage if no parameters
if [[ $# -eq 0 ]]; then
    show_usage
fi

# Run main function
main "$@"