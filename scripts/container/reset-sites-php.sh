#!/bin/bash

# Reset sites.php Script
# Resets the sites.php file to a clean state with only template.decoupled.io pointing to default

set -e

# Configuration
PROJECT_PATH="/var/www/html"
SITES_PHP="$PROJECT_PATH/web/sites/sites.php"

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

# Detect domain suffix from environment or default
detect_domain_suffix() {
    local domain_suffix=""

    # Check environment variable first
    if [[ -n "$DOMAIN_SUFFIX" ]]; then
        domain_suffix="$DOMAIN_SUFFIX"
    # Check .env file
    elif [[ -f "/var/www/html/.env" ]]; then
        domain_suffix=$(grep "DOMAIN_SUFFIX=" /var/www/html/.env | cut -d'=' -f2 || echo "")
    fi

    # Default fallback
    if [[ -z "$domain_suffix" ]]; then
        domain_suffix="decoupled.io"
    fi

    echo "$domain_suffix"
}

# Main function
reset_sites_php() {
    local domain_suffix
    domain_suffix=$(detect_domain_suffix)

    log "Resetting sites.php to clean state..."
    log "Domain suffix: $domain_suffix"

    # Create backup of existing sites.php
    if [[ -f "$SITES_PHP" ]]; then
        local backup_file="$SITES_PHP.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$SITES_PHP" "$backup_file"
        log "Backup created: $backup_file"
    fi

    # Determine template domain - handle different domain suffix formats
    local template_domain
    if [[ "$domain_suffix" == *".localhost" ]] && [[ "$domain_suffix" != "localhost" ]]; then
        # If domain_suffix is already like "template.localhost", use it as-is
        template_domain="$domain_suffix"
    else
        # For domains like "decoupled.io" or "localhost", prepend "template."
        template_domain="template.$domain_suffix"
    fi

    # Create clean sites.php
    cat > "$SITES_PHP" << EOF
<?php

/**
 * @file
 * Configuration file for Drupal's multisite directory aliasing feature.
 *
 * Reset to clean state on $(date)
 */

// Template site (uses default site)
\$sites['$template_domain'] = 'default';
EOF

    # Set proper permissions
    chown www-data:www-data "$SITES_PHP" 2>/dev/null || true
    chmod 644 "$SITES_PHP"

    # Verify syntax
    if php -l "$SITES_PHP" >/dev/null 2>&1; then
        log_success "sites.php reset successfully"
        log "Template domain: $template_domain -> default"
    else
        log_error "sites.php has syntax errors after reset"
        return 1
    fi
}

# Show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Resets sites.php to a clean state with only template domain."
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  -d, --domain   Override domain suffix (default: auto-detect)"
    echo ""
    echo "Examples:"
    echo "  $0                           # Auto-detect domain"
    echo "  $0 -d example.com           # Use example.com as domain"
    echo ""
    echo "Current template mapping will be:"
    echo "  template.[DOMAIN] -> default"
    echo ""
}

# Parse command line arguments
OVERRIDE_DOMAIN=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--domain)
            OVERRIDE_DOMAIN="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Override domain if specified
if [[ -n "$OVERRIDE_DOMAIN" ]]; then
    export DOMAIN_SUFFIX="$OVERRIDE_DOMAIN"
fi

# Main execution
main() {
    echo
    log "Drupal Sites.php Reset Script"
    log "============================="
    echo

    # Check if we're in the right environment
    if [[ ! -f "$PROJECT_PATH/web/index.php" ]]; then
        log_error "Not in a Drupal project directory or running outside container"
        log_error "Expected Drupal at: $PROJECT_PATH"
        exit 1
    fi

    # Show current status
    if [[ -f "$SITES_PHP" ]]; then
        log "Current sites.php exists ($(wc -l < "$SITES_PHP") lines)"
    else
        log "No existing sites.php found"
    fi

    # Perform reset
    reset_sites_php

    echo
    log_success "Sites.php reset completed!"
    echo
    log "Next steps:"
    log "  - Use clone-drupal-site.sh to create new sites"
    log "  - Each new site will be automatically added to sites.php"
    echo
}

# Run main function
main "$@"