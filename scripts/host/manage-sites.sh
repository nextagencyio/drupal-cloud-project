#!/bin/bash
set -e

# Docker-compatible Drupal multisite management script
# Main entry point for all site operations

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTAINER_SCRIPT_DIR="/var/www/html/scripts/container"
DOCKER_COMPOSE_FILE="/opt/drupalcloud/templates/dcloud-docker/docker-compose.prod.yml"
DRUPAL_CONTAINER="drupal"

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
    if docker compose -f "$DOCKER_COMPOSE_FILE" ps --format table 2>/dev/null; then
        echo "✅ Docker containers are running"
    else
        echo "❌ Docker containers may not be running"
        return 1
    fi
    echo
    
    # Delegate to container script for detailed status
    docker compose -f "$DOCKER_COMPOSE_FILE" exec -T "$DRUPAL_CONTAINER" \
        "$CONTAINER_SCRIPT_DIR/get-site-status.sh" --all
}

# Function to validate environment (host-side checks only)
validate_environment() {
    local errors=0
    
    # Check if Docker is available
    if ! command -v docker >/dev/null 2>&1; then
        echo "❌ Docker command not found"
        ((errors++))
    fi
    
    # Check if docker compose file exists
    if [[ ! -f "$DOCKER_COMPOSE_FILE" ]]; then
        echo "❌ Docker Compose file not found: $DOCKER_COMPOSE_FILE"
        ((errors++))
    fi
    
    # Check if containers are running
    if ! docker compose -f "$DOCKER_COMPOSE_FILE" ps --format json 2>/dev/null | grep -q "\"State\":\"running\""; then
        echo "❌ Docker containers are not running"
        ((errors++))
    fi
    
    if [[ $errors -gt 0 ]]; then
        echo "❌ Environment validation failed with $errors errors"
        exit 1
    fi
    
    echo "✅ Host environment validation passed"
}

# Main function - delegates to container scripts
main() {
    local command="${1:-help}"
    
    case "$command" in
        "create")
            validate_environment
            local site_name="$2"
            local space_token="$3"
            local source_site="${4:-template}"
            docker compose -f "$DOCKER_COMPOSE_FILE" exec -T "$DRUPAL_CONTAINER" \
                "$CONTAINER_SCRIPT_DIR/clone-drupal-site.sh" "$site_name" "$space_token" "$source_site"
            ;;
        "delete")
            validate_environment
            shift 1
            docker compose -f "$DOCKER_COMPOSE_FILE" exec -T "$DRUPAL_CONTAINER" \
                "$CONTAINER_SCRIPT_DIR/delete-drupal-site.sh" "$@"
            ;;
        "list")
            shift 1
            docker compose -f "$DOCKER_COMPOSE_FILE" exec -T "$DRUPAL_CONTAINER" \
                "$CONTAINER_SCRIPT_DIR/list-sites.sh" "$@"
            ;;
        "backup")
            validate_environment
            shift 1
            docker compose -f "$DOCKER_COMPOSE_FILE" exec -T "$DRUPAL_CONTAINER" \
                "$CONTAINER_SCRIPT_DIR/backup-site.sh" "$@"
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