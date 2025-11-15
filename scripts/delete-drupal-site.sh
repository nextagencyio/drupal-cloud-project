#!/bin/bash
set -e

# Docker-compatible Drupal site deletion script
# Ported from Jenkins Groovy script to bash for Docker environment

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_PATH="/var/www/html"
SITES_PATH="${PROJECT_PATH}/web/sites"
SITES_PHP="${PROJECT_PATH}/web/sites/sites.php"
# MySQL connection details
MYSQL_HOST="mysql"
MYSQL_USER="drupal"
MYSQL_PASS="drupalpass"

# Function to log messages
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $1"
}

error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $1" >&2
    exit 1
}

warning() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [WARNING] $1" >&2
}

# Function to validate input
validate_space_name() {
    local space_name="$1"
    if [[ ! "$space_name" =~ ^[a-z0-9-]+$ ]]; then
        error "Invalid space name format. Use only lowercase letters, numbers, and hyphens."
    fi
}

# Function to send webhook
send_webhook() {
    local status="$1"
    local space_name="$2"
    local message="$3"
    
    if [[ -n "$WEBHOOK_URL" && -n "$WEBHOOK_SECRET" ]]; then
        local payload=$(cat <<EOF
{
    "type": "site_deletion",
    "status": "$status",
    "space_name": "$space_name",
    "message": "$message",
    "timestamp": $(date +%s)
}
EOF
        )
        
        local signature=$(echo -n "$payload" | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" -binary | xxd -p -c 256)
        
        curl -X POST "$WEBHOOK_URL" \
             -H "Content-Type: application/json" \
             -H "X-Jenkins-Signature: sha256=$signature" \
             -H "X-Jenkins-Timestamp: $(date +%s)" \
             -d "$payload" \
             --max-time 30 \
             --retry 3 \
             --fail \
             --silent \
             --show-error || log "Webhook delivery failed"
    fi
}

# Function to create backup before deletion
create_backup() {
    local space_name="$1"
    local site_dir="$2"
    local db_name="$3"
    local backup_dir="/opt/backups/deleted-sites"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_name="${space_name}_${timestamp}"
    
    log "Creating backup before deletion: $backup_name"
    
    # Create backup directory
    mkdir -p "$backup_dir"
    
    # Export MySQL database
    mysqldump -h "$MYSQL_HOST" -u "$MYSQL_USER" -p"$MYSQL_PASS" "$db_name" > "${backup_dir}/${backup_name}_database.sql" 2>/dev/null || warning "Database backup failed"
    
    # Create backup archive with site files and database dump
    tar -czf "${backup_dir}/${backup_name}.tar.gz" \
        -C "$(dirname "$site_dir")" "$(basename "$site_dir")" \
        -C "$backup_dir" "${backup_name}_database.sql" \
        2>/dev/null || warning "Backup creation failed for some files"
    
    # Clean up temporary database dump
    rm -f "${backup_dir}/${backup_name}_database.sql"
    
    log "Backup created: ${backup_dir}/${backup_name}.tar.gz"
}

# Function to remove site directory
remove_site_directory() {
    local space_name="$1"
    local domain_suffix="${DOMAIN_SUFFIX:-yourdomain.com}"
    local site_dir="${SITES_PATH}/${space_name}.${domain_suffix}"
    
    if [[ -d "$site_dir" ]]; then
        log "Removing site directory: $site_dir"
        rm -rf "$site_dir"
        log "Site directory removed"
    else
        warning "Site directory not found: $site_dir"
    fi
    
    echo "$site_dir"
}

# Function to remove database
remove_database() {
    local space_name="$1"
    local db_name="drupal_${space_name}"
    
    log "Removing MySQL database: $db_name"
    
    # Drop MySQL database
    if mysql -h "$MYSQL_HOST" -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "DROP DATABASE IF EXISTS \`${db_name}\`;" 2>/dev/null; then
        log "MySQL database removed: $db_name"
    else
        warning "Failed to remove MySQL database: $db_name"
    fi
    
    echo "$db_name"
}

# Function to update sites.php
update_sites_php() {
    local space_name="$1"
    local domain_suffix="${DOMAIN_SUFFIX:-yourdomain.com}"
    local site_dir_name="${space_name}.${domain_suffix}"
    
    log "Updating sites.php configuration"
    
    if [[ -f "$SITES_PHP" ]]; then
        # Remove site mapping from sites.php
        sed -i "/\['$site_dir_name'\]/d" "$SITES_PHP"
        log "Removed site mapping from sites.php: $site_dir_name"
    else
        warning "sites.php not found: $SITES_PHP"
    fi
}

# Function to clear caches
clear_drupal_caches() {
    local drush_path="/root/.composer/vendor/bin/drush"
    
    log "Clearing Drupal caches"
    
    cd "$PROJECT_PATH"
    
    # Clear default site cache
    "$drush_path" --uri=default cache:rebuild 2>/dev/null || warning "Failed to clear default site cache"
    
    log "Cache clearing completed"
}

# Main function
main() {
    local space_name="$1"
    local create_backup_flag="${2:-true}"
    
    # Validate inputs
    if [[ -z "$space_name" ]]; then
        error "SPACE_NAME is required"
    fi
    
    validate_space_name "$space_name"
    
    local domain_suffix="${DOMAIN_SUFFIX:-yourdomain.com}"
    local site_uri="https://${space_name}.${domain_suffix}"
    
    log "Starting site deletion for: $space_name"
    log "Site URI: $site_uri"
    
    send_webhook "started" "$space_name" "Site deletion started"
    
    # Check if site exists
    local site_dir="${SITES_PATH}/${space_name}.${domain_suffix}"
    local db_name="drupal_${space_name}"
    
    if [[ ! -d "$site_dir" ]]; then
        warning "Site not found: $space_name"
        send_webhook "completed" "$space_name" "Site not found, nothing to delete"
        return 0
    fi
    
    # Create backup if requested
    if [[ "$create_backup_flag" == "true" ]]; then
        create_backup "$space_name" "$site_dir" "$db_name"
    fi
    
    # Remove site directory
    remove_site_directory "$space_name"
    
    # Remove database
    remove_database "$space_name"
    
    # Update sites.php
    update_sites_php "$space_name"
    
    # Clear Drupal caches
    clear_drupal_caches
    
    log "Site deletion completed successfully for: $space_name"
    send_webhook "completed" "$space_name" "Site deletion completed successfully"
    
    # Output deletion summary
    cat <<EOF

✅ Site Deletion Summary:
   Site Name: $space_name
   Site URI: $site_uri
   Removed Directory: $site_dir
   Removed Database: $db_name
   Backup Created: $create_backup_flag

EOF
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Script is being executed directly
    main "$@"
fi