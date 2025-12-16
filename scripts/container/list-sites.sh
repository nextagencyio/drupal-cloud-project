#!/bin/bash
set -e

# Docker-compatible Drupal site listing script
# Ported from Jenkins Groovy script to bash for Docker environment

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_PATH="/var/www/html"
SITES_PATH="${PROJECT_PATH}/web/sites"
# MySQL connection details
MYSQL_HOST="mysql"
MYSQL_USER="drupal"
MYSQL_PASS="drupalpass"
DRUSH_PATH="/root/.composer/vendor/bin/drush"

# Function to log messages
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $1"
}

error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $1" >&2
    exit 1
}

# Function to get site status
get_site_status() {
    local site_uri="$1"
    local site_dir="$2"
    
    # Check if site directory exists
    if [[ ! -d "$site_dir" ]]; then
        echo "missing"
        return
    fi
    
    # Check if Drupal is installed
    cd "$PROJECT_PATH"
    if "$DRUSH_PATH" --uri="$site_uri" status --field=bootstrap 2>/dev/null | grep -q "Successful"; then
        echo "active"
    else
        echo "inactive"
    fi
}

# Function to get site info
get_site_info() {
    local site_name="$1"
    local site_uri="$2"
    local site_dir="$3"
    local db_file="$4"
    
    local status
    status=$(get_site_status "$site_uri" "$site_dir")
    
    local site_size="0"
    if [[ -d "$site_dir" ]]; then
        site_size=$(du -sh "$site_dir" 2>/dev/null | cut -f1 || echo "0")
    fi
    
    local db_size="0"
    if [[ -f "$db_file" ]]; then
        db_size=$(du -sh "$db_file" 2>/dev/null | cut -f1 || echo "0")
    fi
    
    local last_modified="unknown"
    if [[ -d "$site_dir" ]]; then
        last_modified=$(stat -c %y "$site_dir" 2>/dev/null | cut -d' ' -f1 || echo "unknown")
    fi
    
    echo "$site_name|$site_uri|$status|$site_size|$db_size|$last_modified"
}

# Function to list all sites
list_sites() {
    local format="${1:-table}"
    local domain_suffix="${DOMAIN_SUFFIX:-yourdomain.com}"
    
    log "Scanning for Drupal sites..."
    
    # Array to store site information
    declare -a sites=()
    
    # Scan sites directory for site directories
    if [[ -d "$SITES_PATH" ]]; then
        for site_path in "$SITES_PATH"/*; do
            if [[ -d "$site_path" ]]; then
                local site_dir_name=$(basename "$site_path")
                
                # Skip default and template sites
                if [[ "$site_dir_name" == "default" || "$site_dir_name" == "template" ]]; then
                    continue
                fi
                
                # Extract site name from directory name
                local site_name="${site_dir_name%.$domain_suffix}"
                local site_uri="https://${site_dir_name}"
                local db_name="drupal_${site_name}"
                
                # Get site information
                local site_info
                site_info=$(get_site_info "$site_name" "$site_uri" "$site_path" "$db_name")
                sites+=("$site_info")
            fi
        done
    fi
    
    # Also check for orphaned MySQL databases
    local mysql_dbs
    mysql_dbs=$(mysql -h "$MYSQL_HOST" -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "SHOW DATABASES LIKE 'drupal_%';" -s -N 2>/dev/null || echo "")
    
    if [[ -n "$mysql_dbs" ]]; then
        while IFS= read -r db_name; do
            if [[ -n "$db_name" && "$db_name" =~ ^drupal_ ]]; then
                local site_name="${db_name#drupal_}"
                local site_dir="${SITES_PATH}/${site_name}.${domain_suffix}"
                
                # Check if we already have this site
                local found=false
                for site_info in "${sites[@]}"; do
                    if [[ "$site_info" == "${site_name}|"* ]]; then
                        found=true
                        break
                    fi
                done
                
                # If not found, add as orphaned database
                if [[ "$found" == false ]]; then
                    local site_uri="https://${db_name}.${domain_suffix}"
                    local site_info
                    site_info=$(get_site_info "$db_name" "$site_uri" "$site_dir" "$db_path")
                    sites+=("$site_info")
                fi
            fi
        done
    fi
    
    # Output results
    case "$format" in
        "json")
            echo "["
            local first=true
            for site_info in "${sites[@]}"; do
                IFS='|' read -r name uri status size db_size modified <<< "$site_info"
                if [[ "$first" == true ]]; then
                    first=false
                else
                    echo ","
                fi
                cat <<EOF
    {
        "name": "$name",
        "uri": "$uri",
        "status": "$status",
        "size": "$size",
        "database_size": "$db_size",
        "last_modified": "$modified"
    }
EOF
            done
            echo "]"
            ;;
        "csv")
            echo "name,uri,status,size,database_size,last_modified"
            for site_info in "${sites[@]}"; do
                echo "$site_info" | tr '|' ','
            done
            ;;
        "table"|*)
            printf "%-20s %-40s %-10s %-8s %-8s %-12s\n" "NAME" "URI" "STATUS" "SIZE" "DB_SIZE" "MODIFIED"
            printf "%-20s %-40s %-10s %-8s %-8s %-12s\n" "----" "---" "------" "----" "-------" "--------"
            for site_info in "${sites[@]}"; do
                IFS='|' read -r name uri status size db_size modified <<< "$site_info"
                printf "%-20s %-40s %-10s %-8s %-8s %-12s\n" "$name" "$uri" "$status" "$size" "$db_size" "$modified"
            done
            ;;
    esac
    
    log "Found ${#sites[@]} sites"
}

# Function to get site count
get_site_count() {
    local domain_suffix="${DOMAIN_SUFFIX:-yourdomain.com}"
    local count=0
    
    if [[ -d "$SITES_PATH" ]]; then
        for site_path in "$SITES_PATH"/*; do
            if [[ -d "$site_path" ]]; then
                local site_dir_name=$(basename "$site_path")
                if [[ "$site_dir_name" != "default" && "$site_dir_name" != "template" ]]; then
                    ((count++))
                fi
            fi
        done
    fi
    
    echo "$count"
}

# Main function
main() {
    local action="${1:-list}"
    local format="${2:-table}"
    
    case "$action" in
        "list")
            list_sites "$format"
            ;;
        "count")
            get_site_count
            ;;
        "help")
            cat <<EOF
Usage: $0 [action] [format]

Actions:
  list    - List all sites (default)
  count   - Get site count only
  help    - Show this help

Formats (for list action):
  table   - Table format (default)
  json    - JSON format
  csv     - CSV format

Examples:
  $0                    # List sites in table format
  $0 list json          # List sites in JSON format
  $0 count             # Get site count only
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