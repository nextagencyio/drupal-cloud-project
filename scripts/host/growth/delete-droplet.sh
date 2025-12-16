#!/bin/bash
# DrupalCloud - Delete DigitalOcean Droplet
# Deletes a DigitalOcean droplet by site name or droplet ID
# Usage: ./scripts/host/growth/delete-droplet.sh <site-name-or-droplet-id>

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
    echo "Usage: $0 <site-name-or-droplet-id> [--snapshot]"
    echo ""
    echo "Deletes a DigitalOcean droplet"
    echo ""
    echo "Arguments:"
    echo "  site-name-or-droplet-id  Machine name or droplet ID"
    echo "  --snapshot               Create snapshot before deleting"
    echo ""
    echo "Examples:"
    echo "  $0 mysite1              # Delete by site name"
    echo "  $0 530647315            # Delete by droplet ID"
    echo "  $0 mysite1 --snapshot   # Create snapshot before deleting"
    echo ""
    echo "Prerequisites:"
    echo "  - DIGITALOCEAN_TOKEN environment variable"
    echo "  - doctl CLI installed and authenticated"
    echo ""
}

# Check command line arguments
if [[ $# -lt 1 ]]; then
    log_error "Missing required argument"
    show_usage
    exit 1
fi

IDENTIFIER="$1"
CREATE_SNAPSHOT=false

if [[ "$2" == "--snapshot" ]]; then
    CREATE_SNAPSHOT=true
fi

# Validate environment variables
if [ -z "$DIGITALOCEAN_TOKEN" ]; then
    log_error "DIGITALOCEAN_TOKEN environment variable is required"
    exit 1
fi

log "========================================="
log "DrupalCloud - Delete Droplet"
log "========================================="

# Determine if identifier is a droplet ID or site name
if [[ "$IDENTIFIER" =~ ^[0-9]+$ ]]; then
    # It's a droplet ID
    DROPLET_ID="$IDENTIFIER"
    DROPLET_NAME=$(doctl compute droplet list --format ID,Name --no-header | grep "^${DROPLET_ID}" | awk '{print $2}')
else
    # It's a site name
    SITE_NAME="$IDENTIFIER"
    DROPLET_NAME="drupalcloud-standalone-${SITE_NAME}"
    DROPLET_ID=$(doctl compute droplet list --format Name,ID --no-header | grep "^${DROPLET_NAME}" | awk '{print $2}')
fi

if [ -z "$DROPLET_ID" ]; then
    log_error "Droplet not found: $IDENTIFIER"
    exit 1
fi

# Get droplet details
DROPLET_IP=$(doctl compute droplet list --format ID,PublicIPv4 --no-header | grep "^${DROPLET_ID}" | awk '{print $2}')

log "Droplet found:"
log "  ID: $DROPLET_ID"
log "  Name: $DROPLET_NAME"
log "  IP: $DROPLET_IP"
log "========================================="

# Create snapshot if requested
if [ "$CREATE_SNAPSHOT" = true ]; then
    log_step "Creating snapshot before deletion..."

    SNAPSHOT_NAME="${DROPLET_NAME}-backup-$(date +%s)"

    doctl compute droplet-action snapshot "$DROPLET_ID" \
      --snapshot-name "$SNAPSHOT_NAME" \
      --wait

    log_success "Snapshot created: $SNAPSHOT_NAME"

    # Get snapshot ID
    SNAPSHOT_ID=$(doctl compute snapshot list --format Name,ID --no-header | grep "^${SNAPSHOT_NAME}" | awk '{print $2}')
    log "Snapshot ID: $SNAPSHOT_ID"
fi

# Confirm deletion
log_warning "This will permanently delete the droplet!"
if [ "$CREATE_SNAPSHOT" = true ]; then
    log "A snapshot has been created: $SNAPSHOT_NAME (ID: $SNAPSHOT_ID)"
fi

read -p "Are you sure you want to delete droplet $DROPLET_ID? (yes/no): " CONFIRM

if [[ "$CONFIRM" != "yes" ]]; then
    log "Deletion cancelled"
    exit 0
fi

# Delete the droplet
log_step "Deleting droplet..."

doctl compute droplet delete "$DROPLET_ID" --force

log_success "Droplet deleted successfully"

log "========================================="
log_success "Deletion Complete!"
log "========================================="
log "Deleted droplet: $DROPLET_NAME (ID: $DROPLET_ID)"

if [ "$CREATE_SNAPSHOT" = true ]; then
    log "Snapshot available: $SNAPSHOT_NAME (ID: $SNAPSHOT_ID)"
    log ""
    log "To restore from snapshot:"
    log "  ./clone-from-droplet.sh $SNAPSHOT_ID <new-site-name>"
fi

log "========================================="
