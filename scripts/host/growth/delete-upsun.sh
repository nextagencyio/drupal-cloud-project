#!/bin/bash

# DrupalCloud Delete Growth Plan Script
# Deletes a Growth (Upsun) space and its associated Upsun project
# Usage: ./scripts/host/growth/delete-growth.sh <growth-project-id> <site-machine-name>

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
    echo -e "${BLUE}[DELETE]${NC} $1"
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
    echo "Usage: $0 <growth-project-id> <site-machine-name>"
    echo ""
    echo "Deletes a Growth (Upsun) space and its associated Upsun project"
    echo ""
    echo "Arguments:"
    echo "  growth-project-id   Upsun project ID to delete (e.g., 'qcc2td5lygnac')"
    echo "  site-machine-name   Machine name of the space in database (e.g., 'my-site')"
    echo ""
    echo "Examples:"
    echo "  $0 qcc2td5lygnac my-site"
    echo ""
    echo "Prerequisites:"
    echo "  - Upsun CLI installed and authenticated"
    echo "  - Growth space must exist"
    echo "  - MySQL access to drupalcloud database (for cleanup)"
    echo ""
    echo "WARNING: This action is PERMANENT and cannot be undone!"
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

PROJECT_ID="$1"
SITE_NAME="$2"

log "========================================="
log "DrupalCloud Delete Growth Plan"
log "========================================="
log "Project ID: $PROJECT_ID"
log "Site Name: $SITE_NAME"
log "========================================="

# Validate prerequisites
validate_prerequisites

# Step 1: Verify project exists
log_step "1/3 Verifying Growth project exists..."

if ! upsun project:info -p "$PROJECT_ID" &> /dev/null; then
    log_error "Project not found: $PROJECT_ID"
    log "Project may have already been deleted"
    log_warning "Skipping Upsun deletion, but you should still update the database"
    exit 1
fi

# Get project details before deletion
PROJECT_INFO=$(upsun project:info -p "$PROJECT_ID" --format=json 2>&1 || echo "{}")
PROJECT_TITLE=$(echo "$PROJECT_INFO" | jq -r '.title // "Unknown"' 2>/dev/null || echo "Unknown")
PROJECT_URL=$(upsun environment:info -p "$PROJECT_ID" -e main url 2>&1 | grep -oP 'https://[^\s]+' || echo "Unknown")

log_success "Project verified:"
log "  Title: $PROJECT_TITLE"
log "  URL: $PROJECT_URL"

# Step 2: Confirm deletion (interactive safety check)
log_warning "⚠️  WARNING: You are about to permanently delete this Growth space!"
log "Project ID: $PROJECT_ID"
log "Project Title: $PROJECT_TITLE"
log "Project URL: $PROJECT_URL"
log ""
log "This action will:"
log "  • Delete the Upsun project and all its data"
log "  • Remove all backups and environments"
log "  • Cannot be undone"
log ""

read -p "Type 'DELETE' to confirm deletion: " CONFIRM

if [[ "$CONFIRM" != "DELETE" ]]; then
    log "Deletion cancelled"
    exit 0
fi

# Step 3: Delete Upsun project
log_step "2/3 Deleting Upsun project..."

log "Deleting project from Upsun..."
if upsun project:delete -p "$PROJECT_ID" --yes --no-wait 2>&1; then
    log_success "Upsun project deletion initiated"
else
    log_error "Failed to delete Upsun project"
    log "You may need to delete it manually from: https://console.upsun.com/"
    exit 1
fi

# Wait a moment for deletion to process
sleep 5

# Verify deletion
log "Verifying project deletion..."
if upsun project:info -p "$PROJECT_ID" &> /dev/null; then
    log_warning "Project still exists (deletion may be in progress)"
    log "Check status at: https://console.upsun.com/"
else
    log_success "Project deleted from Upsun"
fi

# Step 4: Database cleanup
log_step "3/3 Updating database..."

log "Database cleanup instructions:"
log ""
log "Run the following SQL to mark the space as deleted:"
log ""
log "UPDATE spaces SET"
log "  drupal_site_status='deleted',"
log "  updated_at=NOW()"
log "WHERE machine_name='$SITE_NAME' AND growth_project_id='$PROJECT_ID';"
log ""
log "Or, to completely remove the space from the database:"
log ""
log "DELETE FROM spaces"
log "WHERE machine_name='$SITE_NAME' AND growth_project_id='$PROJECT_ID';"
log ""

# Display summary
log "========================================="
log_success "Growth Plan Deletion Complete!"
log "========================================="
log "Project ID: $PROJECT_ID"
log "Site Name: $SITE_NAME"
log "========================================="
log ""
log_warning "Important:"
log "• Update the database to mark the space as deleted"
log "• The Upsun project and all its data have been permanently deleted"
log "• Backups have also been deleted"
log "• This action cannot be undone"
log ""
