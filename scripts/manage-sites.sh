#!/bin/bash
set -e

# Docker-compatible Drupal multisite management script
# Main entry point for all site operations

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Function to show help
show_help() {
    cat <<EOF
Drupal Multisite Management Script (Docker Edition)

Usage: $0 <command> [options]

Commands:
  create <space_name> <space_token>     - Create a new Drupal site
  delete <space_name> [no-backup]       - Delete a Drupal site
  list [format]                         - List all sites
  backup <space_name> [type]            - Backup a site
  status                               - Show system status
  help                                 - Show this help

Examples:
  $0 create mysite space_tok_abc123...
  $0 delete mysite
  $0 list json
  $0 backup mysite full
  $0 status

Environment Variables:
  DOMAIN_SUFFIX     - Domain suffix for sites (default: yourdomain.com)
  WEBHOOK_URL       - URL for status webhooks
  WEBHOOK_SECRET    - Secret for webhook authentication

EOF
}

# Function to show system status
show_status() {
    echo "=== Drupal Multisite System Status ==="
    echo
    
    # Docker status
    echo "Docker Status:"
    if docker compose -f /opt/drupalcloud/templates/dcloud-docker/docker-compose.prod.yml ps --format table 2>/dev/null; then
        echo "✅ Docker containers are running"
    else
        echo "❌ Docker containers may not be running"
    fi
    echo
    
    # Disk usage
    echo "Disk Usage:"
    df -h /var/www/html 2>/dev/null || echo "Unable to check disk usage"
    echo
    
    # Site count
    echo "Site Statistics:"
    local site_count
    site_count=$("$SCRIPT_DIR/list-sites.sh" count 2>/dev/null || echo "0")
    echo "Total Sites: $site_count"
    echo
    
    # Recent backups
    echo "Recent Backups:"
    if [[ -d "/opt/backups" ]]; then
        local backup_count
        backup_count=$(find /opt/backups -name "*.tar.gz" -type f -mtime -7 | wc -l)
        echo "Backups (last 7 days): $backup_count"
    else
        echo "Backup directory not found"
    fi
    echo
    
    # Database Information
    echo "Database Information:"
    echo "Using MySQL for production (SQLite checks removed)"
    echo
}

# Function to validate environment
validate_environment() {
    local errors=0
    
    # Check if running in container
    if [[ ! -f "/.dockerenv" ]]; then
        echo "⚠️  Warning: Not running in Docker container"
    fi
    
    # Check required directories
    local required_dirs=(
        "/var/www/html"
        "/var/www/html/web"
        "/var/www/html/web/sites"
        # SQLite directory removed - using MySQL
    )
    
    for dir in "${required_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            echo "❌ Required directory missing: $dir"
            ((errors++))
        fi
    done
    
    # Check required commands
    local required_commands=(
        "drush"
        "composer"
        # sqlite3 removed - using MySQL
    )
    
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            echo "❌ Required command missing: $cmd"
            ((errors++))
        fi
    done
    
    if [[ $errors -gt 0 ]]; then
        echo "❌ Environment validation failed with $errors errors"
        exit 1
    fi
    
    echo "✅ Environment validation passed"
}

# Main function
main() {
    local command="${1:-help}"
    
    case "$command" in
        "create")
            validate_environment
            "$SCRIPT_DIR/create-drupal-site.sh" "$2" "$3"
            ;;
        "delete")
            validate_environment
            local backup_flag="true"
            if [[ "$3" == "no-backup" ]]; then
                backup_flag="false"
            fi
            "$SCRIPT_DIR/delete-drupal-site.sh" "$2" "$backup_flag"
            ;;
        "list")
            "$SCRIPT_DIR/list-sites.sh" "list" "$2"
            ;;
        "backup")
            validate_environment
            "$SCRIPT_DIR/backup-site.sh" "backup" "$2" "$3"
            ;;
        "status")
            show_status
            ;;
        "validate")
            validate_environment
            ;;
        "help"|*)
            show_help
            ;;
    esac
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Script is being executed directly
    main "$@"
fi