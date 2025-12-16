#!/bin/bash
set -e

# Docker-compatible Drupal site backup script
# Ported from Jenkins Groovy script to bash for Docker environment

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_PATH="/var/www/html"
SITES_PATH="${PROJECT_PATH}/web/sites"
# MySQL connection details
MYSQL_HOST="mysql"
MYSQL_USER="drupal"
MYSQL_PASS="drupalpass"
BACKUP_PATH="/opt/backups"

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
    "type": "site_backup",
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

# Function to create site backup
create_site_backup() {
    local space_name="$1"
    local backup_type="${2:-full}"
    local domain_suffix="${DOMAIN_SUFFIX:-yourdomain.com}"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    
    local site_dir="${SITES_PATH}/${space_name}.${domain_suffix}"
    local db_name="drupal_${space_name}"
    local backup_name="${space_name}_${backup_type}_${timestamp}"
    local backup_file="${BACKUP_PATH}/${backup_name}.tar.gz"
    
    log "Creating $backup_type backup for: $space_name"
    
    # Create backup directory
    mkdir -p "$BACKUP_PATH"
    
    # Check if site exists (check MySQL database)
    local db_exists
    db_exists=$(mysql -h "$MYSQL_HOST" -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "SHOW DATABASES LIKE '$db_name';" -s -N 2>/dev/null || echo "")
    
    if [[ ! -d "$site_dir" && -z "$db_exists" ]]; then
        error "Site not found: $space_name"
    fi
    
    # Create backup based on type
    case "$backup_type" in
        "full")
            create_full_backup "$space_name" "$site_dir" "$db_file" "$backup_file"
            ;;
        "files")
            create_files_backup "$space_name" "$site_dir" "$backup_file"
            ;;
        "database")
            create_database_backup "$space_name" "$db_file" "$backup_file"
            ;;
        *)
            error "Unknown backup type: $backup_type"
            ;;
    esac
    
    # Get backup size
    local backup_size
    if [[ -f "$backup_file" ]]; then
        backup_size=$(du -sh "$backup_file" | cut -f1)
        log "Backup created: $backup_file ($backup_size)"
    else
        error "Backup file was not created"
    fi
    
    echo "$backup_file"
}

# Function to create full backup
create_full_backup() {
    local space_name="$1"
    local site_dir="$2"
    local db_file="$3"
    local backup_file="$4"
    
    log "Creating full backup (files + database)"
    
    # Create temporary manifest
    local manifest_file="/tmp/${space_name}_manifest.txt"
    cat > "$manifest_file" <<EOF
# Backup Manifest
# Created: $(date)
# Site: $space_name
# Type: full

Site Directory: $site_dir
Database File: $db_file
Backup File: $backup_file
EOF
    
    # Create backup archive
    local tar_files=()
    
    if [[ -d "$site_dir" ]]; then
        tar_files+=(-C "$(dirname "$site_dir")" "$(basename "$site_dir")")
    fi
    
    if [[ -f "$db_file" ]]; then
        tar_files+=(-C "$(dirname "$db_file")" "$(basename "$db_file")")
    fi
    
    tar_files+=(-C "$(dirname "$manifest_file")" "$(basename "$manifest_file")")
    
    tar -czf "$backup_file" "${tar_files[@]}"
    
    # Cleanup manifest
    rm -f "$manifest_file"
}

# Function to create files-only backup
create_files_backup() {
    local space_name="$1"
    local site_dir="$2"
    local backup_file="$3"
    
    log "Creating files-only backup"
    
    if [[ ! -d "$site_dir" ]]; then
        error "Site directory not found: $site_dir"
    fi
    
    tar -czf "$backup_file" -C "$(dirname "$site_dir")" "$(basename "$site_dir")"
}

# Function to create database-only backup
create_database_backup() {
    local space_name="$1"
    local db_file="$2"
    local backup_file="$3"
    
    log "Creating database-only backup"
    
    if [[ ! -f "$db_file" ]]; then
        error "Database file not found: $db_file"
    fi
    
    tar -czf "$backup_file" -C "$(dirname "$db_file")" "$(basename "$db_file")"
}

# Function to list backups
list_backups() {
    local space_name="${1:-*}"
    local format="${2:-table}"
    
    log "Listing backups for: $space_name"
    
    # Find backup files
    local backup_files=()
    while IFS= read -r -d '' file; do
        backup_files+=("$file")
    done < <(find "$BACKUP_PATH" -name "${space_name}_*.tar.gz" -type f -print0 2>/dev/null)
    
    if [[ ${#backup_files[@]} -eq 0 ]]; then
        log "No backups found for: $space_name"
        return
    fi
    
    # Sort by modification time (newest first)
    IFS=$'\n' backup_files=($(sort -r <<<"${backup_files[*]}"))
    
    case "$format" in
        "json")
            echo "["
            local first=true
            for backup_file in "${backup_files[@]}"; do
                local backup_name=$(basename "$backup_file" .tar.gz)
                local backup_size=$(du -sh "$backup_file" | cut -f1)
                local backup_date=$(stat -c %y "$backup_file" | cut -d' ' -f1)
                
                if [[ "$first" == true ]]; then
                    first=false
                else
                    echo ","
                fi
                cat <<EOF
    {
        "name": "$backup_name",
        "file": "$backup_file",
        "size": "$backup_size",
        "date": "$backup_date"
    }
EOF
            done
            echo "]"
            ;;
        "table"|*)
            printf "%-40s %-60s %-8s %-12s\n" "BACKUP NAME" "FILE PATH" "SIZE" "DATE"
            printf "%-40s %-60s %-8s %-12s\n" "-----------" "---------" "----" "----"
            for backup_file in "${backup_files[@]}"; do
                local backup_name=$(basename "$backup_file" .tar.gz)
                local backup_size=$(du -sh "$backup_file" | cut -f1)
                local backup_date=$(stat -c %y "$backup_file" | cut -d' ' -f1)
                printf "%-40s %-60s %-8s %-12s\n" "$backup_name" "$backup_file" "$backup_size" "$backup_date"
            done
            ;;
    esac
}

# Function to cleanup old backups
cleanup_backups() {
    local space_name="${1:-*}"
    local keep_days="${2:-30}"
    
    log "Cleaning up backups older than $keep_days days for: $space_name"
    
    local deleted_count=0
    while IFS= read -r -d '' file; do
        log "Deleting old backup: $file"
        rm -f "$file"
        ((deleted_count++))
    done < <(find "$BACKUP_PATH" -name "${space_name}_*.tar.gz" -type f -mtime +$keep_days -print0 2>/dev/null)
    
    log "Deleted $deleted_count old backup(s)"
}

# Main function
main() {
    local action="${1:-backup}"
    local space_name="$2"
    local backup_type="${3:-full}"
    
    case "$action" in
        "backup")
            if [[ -z "$space_name" ]]; then
                error "Space name is required for backup action"
            fi
            validate_space_name "$space_name"
            send_webhook "started" "$space_name" "Backup started"
            backup_file=$(create_site_backup "$space_name" "$backup_type")
            send_webhook "completed" "$space_name" "Backup completed: $(basename "$backup_file")"
            ;;
        "list")
            list_backups "$space_name" "$backup_type"
            ;;
        "cleanup")
            cleanup_backups "$space_name" "$backup_type"
            ;;
        "help")
            cat <<EOF
Usage: $0 [action] [space_name] [backup_type|format|days]

Actions:
  backup   - Create backup for specified site
  list     - List backups (optional site name filter)
  cleanup  - Remove old backups (optional site name filter)
  help     - Show this help

Backup Types (for backup action):
  full     - Full backup (files + database) [default]
  files    - Files only backup
  database - Database only backup

Examples:
  $0 backup mysite full           # Create full backup for mysite
  $0 backup mysite files          # Create files-only backup
  $0 list mysite                  # List backups for mysite
  $0 list                         # List all backups
  $0 cleanup mysite 7             # Remove backups older than 7 days for mysite
  $0 cleanup "*" 30               # Remove all backups older than 30 days
EOF
            ;;
        *)
            error "Unknown action: $action. Use 'help' for usage information."
            ;;
    esac
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Script is being executed directly
    main "$@"
fi