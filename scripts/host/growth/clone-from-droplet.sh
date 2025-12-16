#!/bin/bash
# DrupalCloud - Clone from DigitalOcean Droplet (Snapshot-based)
# Creates a new droplet from an existing snapshot
# Usage: ./scripts/host/growth/clone-from-droplet.sh <snapshot-id> <new-site-name>

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
    echo -e "${BLUE}[CLONE]${NC} $1"
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
    echo "Usage: $0 <snapshot-id> <new-site-name> [droplet-size] [region]"
    echo ""
    echo "Clones a DigitalOcean droplet from a snapshot"
    echo ""
    echo "Arguments:"
    echo "  snapshot-id       DigitalOcean snapshot ID"
    echo "  new-site-name     Machine name for the new site"
    echo "  droplet-size      Droplet size (default: s-2vcpu-4gb)"
    echo "  region            Region (default: nyc1)"
    echo ""
    echo "Examples:"
    echo "  $0 206860612 newsite1         # Clone with defaults"
    echo "  $0 206860612 newsite2 s-4vcpu-8gb sfo3  # Custom size and region"
    echo ""
    echo "Prerequisites:"
    echo "  - DIGITALOCEAN_TOKEN environment variable"
    echo "  - DIGITALOCEAN_SSH_KEY_ID environment variable"
    echo "  - doctl CLI installed and authenticated"
    echo ""
}

# Check command line arguments
if [[ $# -lt 2 ]]; then
    log_error "Invalid number of arguments"
    show_usage
    exit 1
fi

SNAPSHOT_ID="$1"
SITE_NAME="$2"
DROPLET_SIZE="${3:-s-2vcpu-4gb}"
REGION="${4:-nyc1}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Validate environment variables
if [ -z "$DIGITALOCEAN_TOKEN" ]; then
    log_error "DIGITALOCEAN_TOKEN environment variable is required"
    exit 1
fi

if [ -z "$DIGITALOCEAN_SSH_KEY_ID" ]; then
    log_error "DIGITALOCEAN_SSH_KEY_ID environment variable is required"
    exit 1
fi

log "========================================="
log "DrupalCloud - Clone from Droplet Snapshot"
log "========================================="
log "Snapshot ID: $SNAPSHOT_ID"
log "New site name: $SITE_NAME"
log "Droplet size: $DROPLET_SIZE"
log "Region: $REGION"
log "========================================="

START_TIME=$(date +%s)

# Step 1: Create droplet from snapshot
log_step "1/2 Creating droplet from snapshot..."

DROPLET_NAME="drupalcloud-standalone-${SITE_NAME}"

doctl compute droplet create "$DROPLET_NAME" \
  --image "$SNAPSHOT_ID" \
  --size "$DROPLET_SIZE" \
  --region "$REGION" \
  --ssh-keys "$DIGITALOCEAN_SSH_KEY_ID" \
  --tag-names "drupalcloud,growth,site-${SITE_NAME}" \
  --wait

log_success "Droplet created"

# Get droplet details
DROPLET_IP=$(doctl compute droplet list --format Name,PublicIPv4 --no-header | grep "^${DROPLET_NAME}" | awk '{print $2}')
DROPLET_ID=$(doctl compute droplet list --format Name,ID --no-header | grep "^${DROPLET_NAME}" | awk '{print $2}')

if [ -z "$DROPLET_IP" ] || [ -z "$DROPLET_ID" ]; then
    log_error "Could not retrieve droplet details"
    exit 1
fi

log "Droplet ID: $DROPLET_ID"
log "Droplet IP: $DROPLET_IP"

# Step 2: Wait for SSH and verify
log_step "2/2 Waiting for SSH access..."

MAX_ATTEMPTS=30
ATTEMPT=0
while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
  if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@$DROPLET_IP "echo 'ready'" &>/dev/null; then
    log_success "SSH is ready"
    break
  fi
  ATTEMPT=$((ATTEMPT + 1))
  log "Attempt $ATTEMPT/$MAX_ATTEMPTS..."
  sleep 10
done

if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
    log_warning "SSH did not become available within expected time"
fi

# Calculate total time
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
MINUTES=$((DURATION / 60))
SECONDS=$((DURATION % 60))

log "========================================="
log_success "Clone Complete!"
log "========================================="
log "Site name: $SITE_NAME"
log "Droplet ID: $DROPLET_ID"
log "Droplet IP: $DROPLET_IP"
log "Site URL: http://$DROPLET_IP"
log "Region: $REGION"
log "Time taken: ${MINUTES}m ${SECONDS}s"
log "========================================="
log ""
log "Next steps:"
log "1. Visit http://$DROPLET_IP to verify the site"
log "2. Update DNS to point to $DROPLET_IP"
log "3. Change admin password for security"
log ""
log "To delete this droplet:"
log "  doctl compute droplet delete $DROPLET_ID"
log ""
