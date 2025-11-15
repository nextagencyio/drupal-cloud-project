#!/bin/bash

# Get Drupal Site Status Script
# Provides detailed status information for a specific Drupal site

set -e

# Configuration
PROJECT_PATH="/var/www/html"
SITES_PATH="$PROJECT_PATH/web/sites"
DRUSH_PATH="$PROJECT_PATH/vendor/bin/drush"

# MySQL connection details
MYSQL_HOST="mysql"
MYSQL_USER="drupal"
MYSQL_PASS="drupalpass"

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

# Function to show usage
show_usage() {
    echo "Usage: $0 <SITE_NAME> [OPTIONS]"
    echo ""
    echo "Get detailed status information for a specific Drupal site."
    echo ""
    echo "Arguments:"
    echo "  SITE_NAME           Name of the site to check (e.g., mysite)"
    echo ""
    echo "Options:"
    echo "  -f, --format FORMAT Output format: table|json|summary (default: table)"
    echo "  -h, --help          Show this help message"
    echo "  --domain DOMAIN     Override domain suffix (default: auto-detect)"
    echo ""
    echo "Examples:"
    echo "  $0 mysite                    # Basic status check"
    echo "  $0 mysite --format json      # JSON output"
    echo "  $0 mysite --format summary   # Brief summary"
    echo ""
}

# Function to detect domain suffix
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

# Function to check database connectivity
check_database() {
    local db_name="$1"
    local db_info="{}"

    if mysql -h "$MYSQL_HOST" -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "USE \`$db_name\`;" 2>/dev/null; then
        local table_count
        table_count=$(mysql -h "$MYSQL_HOST" -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$db_name';" -N 2>/dev/null || echo "0")

        local db_size
        db_size=$(mysql -h "$MYSQL_HOST" -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS 'size_mb' FROM information_schema.tables WHERE table_schema='$db_name';" -N 2>/dev/null || echo "0")

        if [[ "$FORMAT" == "json" ]]; then
            echo "{\"connection\":\"ok\",\"tables\":$table_count,\"size_mb\":\"$db_size\"}"
        else
            echo "ok|$table_count|${db_size}MB"
        fi
    else
        if [[ "$FORMAT" == "json" ]]; then
            echo "{\"connection\":\"error\",\"tables\":0,\"size_mb\":\"0\"}"
        else
            echo "error|0|0MB"
        fi
    fi
}

# Function to check Drupal status
check_drupal_status() {
    local site_uri="$1"
    local site_dir="$2"

    cd "$PROJECT_PATH"

    # Check if site directory exists
    if [[ ! -d "$site_dir" ]]; then
        if [[ "$FORMAT" == "json" ]]; then
            echo "{\"status\":\"missing\",\"bootstrap\":\"failed\",\"version\":null}"
        else
            echo "missing|failed|unknown"
        fi
        return
    fi

    # Try to get Drupal status
    local bootstrap="unknown"
    local version="unknown"
    local status="unknown"

    if timeout 30 "$DRUSH_PATH" --uri="$site_uri" status --field=bootstrap 2>/dev/null | grep -q "Successful"; then
        bootstrap="successful"
        status="active"

        # Get Drupal version
        version=$("$DRUSH_PATH" --uri="$site_uri" status --field=drupal-version 2>/dev/null || echo "unknown")
    else
        bootstrap="failed"
        status="inactive"
    fi

    if [[ "$FORMAT" == "json" ]]; then
        echo "{\"status\":\"$status\",\"bootstrap\":\"$bootstrap\",\"version\":\"$version\"}"
    else
        echo "$status|$bootstrap|$version"
    fi
}

# Function to check file system
check_filesystem() {
    local site_dir="$1"

    if [[ ! -d "$site_dir" ]]; then
        if [[ "$FORMAT" == "json" ]]; then
            echo "{\"public_size\":\"0\",\"private_size\":\"0\",\"total_size\":\"0\"}"
        else
            echo "0|0|0"
        fi
        return
    fi

    local public_size="0"
    local private_size="0"
    local total_size="0"

    if [[ -d "$site_dir/files" ]]; then
        public_size=$(du -sh "$site_dir/files" 2>/dev/null | cut -f1 || echo "0")
    fi

    if [[ -d "$site_dir/private" ]]; then
        private_size=$(du -sh "$site_dir/private" 2>/dev/null | cut -f1 || echo "0")
    fi

    total_size=$(du -sh "$site_dir" 2>/dev/null | cut -f1 || echo "0")

    if [[ "$FORMAT" == "json" ]]; then
        echo "{\"public_size\":\"$public_size\",\"private_size\":\"$private_size\",\"total_size\":\"$total_size\"}"
    else
        echo "$public_size|$private_size|$total_size"
    fi
}

# Function to check site configuration
check_site_config() {
    local site_name="$1"
    local site_dir="$2"
    local domain_suffix="$3"

    local config_file="$site_dir/settings.php"
    local space_json="$site_dir/space.json"

    local settings_ok="false"
    local space_token="unknown"
    local created_at="unknown"

    # Check if settings.php exists and is readable
    if [[ -f "$config_file" && -r "$config_file" ]]; then
        settings_ok="true"
    fi

    # Check space.json if it exists
    if [[ -f "$space_json" && -r "$space_json" ]]; then
        space_token=$(grep -o '"spaceToken":"[^"]*"' "$space_json" 2>/dev/null | cut -d'"' -f4 || echo "unknown")
        created_at=$(grep -o '"createdAt":"[^"]*"' "$space_json" 2>/dev/null | cut -d'"' -f4 || echo "unknown")
    fi

    if [[ "$FORMAT" == "json" ]]; then
        echo "{\"settings_file\":\"$settings_ok\",\"space_token\":\"$space_token\",\"created_at\":\"$created_at\"}"
    else
        echo "$settings_ok|$space_token|$created_at"
    fi
}

# Function to output in table format
output_table() {
    local site_name="$1"
    local site_uri="$2"
    local drupal_info="$3"
    local db_info="$4"
    local fs_info="$5"
    local config_info="$6"

    echo ""
    echo "======================================"
    echo "Site Status Report: $site_name"
    echo "======================================"
    echo ""

    # Parse the pipe-separated values
    IFS='|' read -r drupal_status drupal_bootstrap drupal_version <<< "$drupal_info"
    IFS='|' read -r db_status db_tables db_size <<< "$db_info"
    IFS='|' read -r public_size private_size total_size <<< "$fs_info"
    IFS='|' read -r settings_ok space_token created_at <<< "$config_info"

    echo "🌐 Site Information:"
    echo "   Name: $site_name"
    echo "   URL: $site_uri"
    echo "   Status: $drupal_status"
    echo ""

    echo "🐘 Drupal Information:"
    echo "   Bootstrap: $drupal_bootstrap"
    echo "   Version: $drupal_version"
    echo ""

    echo "🗄️ Database Information:"
    echo "   Connection: $db_status"
    echo "   Tables: $db_tables"
    echo "   Size: $db_size"
    echo ""

    echo "📁 File System:"
    echo "   Public Files: $public_size"
    echo "   Private Files: $private_size"
    echo "   Total Size: $total_size"
    echo ""

    echo "⚙️ Configuration:"
    echo "   Settings File: $settings_ok"
    echo "   Space Token: ${space_token:0:16}..."
    echo "   Created: $created_at"
    echo ""

    # Overall health assessment
    if [[ "$drupal_status" == "active" && "$db_status" == "ok" && "$settings_ok" == "true" ]]; then
        log_success "Site is healthy and operational"
    elif [[ "$drupal_status" == "inactive" ]]; then
        log_warning "Site is inactive - may need attention"
    else
        log_error "Site has issues - requires investigation"
    fi
}

# Function to output in JSON format
output_json() {
    local site_name="$1"
    local site_uri="$2"
    local drupal_info="$3"
    local db_info="$4"
    local fs_info="$5"
    local config_info="$6"

    echo "{"
    echo "  \"site_name\": \"$site_name\","
    echo "  \"site_uri\": \"$site_uri\","
    echo "  \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
    echo "  \"drupal\": $drupal_info,"
    echo "  \"database\": $db_info,"
    echo "  \"filesystem\": $fs_info,"
    echo "  \"configuration\": $config_info"
    echo "}"
}

# Function to output summary format
output_summary() {
    local site_name="$1"
    local drupal_info="$3"
    local db_info="$4"

    IFS='|' read -r drupal_status drupal_bootstrap drupal_version <<< "$drupal_info"
    IFS='|' read -r db_status db_tables db_size <<< "$db_info"

    if [[ "$drupal_status" == "active" && "$db_status" == "ok" ]]; then
        echo "✅ $site_name: HEALTHY (Drupal $drupal_version, $db_tables tables, $db_size)"
    elif [[ "$drupal_status" == "inactive" ]]; then
        echo "⚠️  $site_name: INACTIVE (Bootstrap: $drupal_bootstrap)"
    else
        echo "❌ $site_name: ERROR (Status: $drupal_status, DB: $db_status)"
    fi
}

# Main function
main() {
    local site_name="$1"
    local domain_suffix
    domain_suffix=$(detect_domain_suffix)

    if [[ -z "$site_name" ]]; then
        log_error "Site name is required"
        show_usage
        exit 1
    fi

    # Construct paths and URIs
    local site_dir="$SITES_PATH/$site_name"
    local site_uri="https://${site_name}.${domain_suffix}"
    local db_name="drupal_${site_name}"

    log "Checking status for site: $site_name"
    log "Domain: ${site_name}.${domain_suffix}"

    # Gather status information
    local drupal_info
    local db_info
    local fs_info
    local config_info

    drupal_info=$(check_drupal_status "$site_uri" "$site_dir")
    db_info=$(check_database "$db_name")
    fs_info=$(check_filesystem "$site_dir")
    config_info=$(check_site_config "$site_name" "$site_dir" "$domain_suffix")

    # Output in requested format
    case "$FORMAT" in
        "json")
            output_json "$site_name" "$site_uri" "$drupal_info" "$db_info" "$fs_info" "$config_info"
            ;;
        "summary")
            output_summary "$site_name" "$site_uri" "$drupal_info" "$db_info"
            ;;
        *)
            output_table "$site_name" "$site_uri" "$drupal_info" "$db_info" "$fs_info" "$config_info"
            ;;
    esac
}

# Parse command line arguments
SITE_NAME=""
FORMAT="table"
DOMAIN_OVERRIDE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--format)
            FORMAT="$2"
            shift 2
            ;;
        --domain)
            DOMAIN_OVERRIDE="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        -*)
            log_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
        *)
            if [[ -z "$SITE_NAME" ]]; then
                SITE_NAME="$1"
            else
                log_error "Too many arguments"
                show_usage
                exit 1
            fi
            shift
            ;;
    esac
done

# Override domain suffix if provided
if [[ -n "$DOMAIN_OVERRIDE" ]]; then
    export DOMAIN_SUFFIX="$DOMAIN_OVERRIDE"
fi

# Validate format
if [[ "$FORMAT" != "table" && "$FORMAT" != "json" && "$FORMAT" != "summary" ]]; then
    log_error "Invalid format: $FORMAT. Use table, json, or summary."
    exit 1
fi

# Run main function
main "$SITE_NAME"