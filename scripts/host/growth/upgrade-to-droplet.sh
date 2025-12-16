#!/bin/bash
# DrupalCloud Growth Plan Upgrade Script - DigitalOcean Standalone
# Migrates a Starter space (multisite) to Growth plan (DigitalOcean droplet)
# Usage: ./upgrade-to-droplet.sh <site_name> <space_id> [droplet_size] [region]

set -e

# Parse arguments
SITE_NAME="$1"
SPACE_ID="$2"
DROPLET_SIZE="${3:-s-2vcpu-4gb}"
REGION="${4:-nyc1}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Logging functions
log() {
    echo -e "${BLUE}[UPGRADE]${NC} $1"
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

if [ -z "$SITE_NAME" ] || [ -z "$SPACE_ID" ]; then
  log_error "Missing required arguments"
  echo "Usage: $0 <site_name> <space_id> [droplet_size] [region]"
  exit 1
fi

if [ -z "$DIGITALOCEAN_TOKEN" ]; then
  log_error "DIGITALOCEAN_TOKEN environment variable is required"
  exit 1
fi

echo -e "${GREEN}==================================================================${NC}"
echo -e "${GREEN}Upgrading Multisite Space to Standalone DigitalOcean Droplet${NC}"
echo -e "${GREEN}==================================================================${NC}"
echo "  Site name: $SITE_NAME"
echo "  Space ID: $SPACE_ID"
echo "  Droplet size: $DROPLET_SIZE"
echo "  Region: $REGION"
echo -e "${GREEN}==================================================================${NC}"
echo ""

START_TIME=$(date +%s)
START_DISPLAY=$(date '+%Y-%m-%d %H:%M:%S')
echo -e "${YELLOW}Starting upgrade at: $START_DISPLAY${NC}"
echo ""

# Detect environment
if [[ -d "/opt/drupalcloud" ]] && [[ ! -d "/Users" ]]; then
    # Linux server (production)
    log "Environment: Production (Linux)"
    ENVIRONMENT="production"
    COMPOSE_FILE="docker-compose.prod.yml"
    PROJECT_ROOT="/opt/drupalcloud"
    SERVICE_NAME="drupal"  # Service name in compose file, not container name
else
    # Mac development
    log "Environment: Development (Mac)"
    ENVIRONMENT="development"
    COMPOSE_FILE="docker-compose.local.yml"
    PROJECT_ROOT="$(pwd)"
    while [[ ! -f "$PROJECT_ROOT/docker-compose.local.yml" ]] && [[ "$PROJECT_ROOT" != "/" ]]; do
        PROJECT_ROOT="$(dirname "$PROJECT_ROOT")"
    done
    if [[ ! -f "$PROJECT_ROOT/docker-compose.local.yml" ]]; then
        log_error "Cannot find docker-compose.local.yml"
        exit 1
    fi
    SERVICE_NAME="drupal"
fi

cd "$PROJECT_ROOT"
log "Working directory: $PROJECT_ROOT"

# Create temp directory for export
TEMP_DIR="/tmp/drupalcloud-export-${SITE_NAME}-${TIMESTAMP}"
mkdir -p "$TEMP_DIR"
log "Created temp directory: $TEMP_DIR"

# ============================================================================
# STEP 1: Export database and files from multisite
# ============================================================================
log_step "Exporting database and files from multisite..."

# Export database
log "Exporting database..."
docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE_NAME" \
    /var/www/html/vendor/bin/drush --uri="https://${SITE_NAME}.decoupled.io" \
    sql:dump \
    --extra-dump=--default-character-set=utf8mb4 \
    --gzip \
    --result-file="/tmp/${SITE_NAME}.sql" \
    || { log_error "Database export failed"; exit 1; }

# Copy database dump from container
docker compose -f "$COMPOSE_FILE" cp \
    "${SERVICE_NAME}:/tmp/${SITE_NAME}.sql.gz" \
    "${TEMP_DIR}/database.sql.gz" \
    || { log_error "Failed to copy database dump"; exit 1; }

# Extract and fix collation
log "Fixing database collation..."
gunzip "${TEMP_DIR}/database.sql.gz"
sed -i 's/utf8mb4_uca1400_ai_ci/utf8mb4_unicode_ci/g' "${TEMP_DIR}/database.sql"
gzip "${TEMP_DIR}/database.sql"

log_success "Database exported: ${TEMP_DIR}/database.sql.gz"

# Export files
log "Exporting files..."
docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE_NAME" \
    tar czf "/tmp/${SITE_NAME}-files.tar.gz" \
    -C "/var/www/html/web/sites/${SITE_NAME}" files \
    || { log_error "Files export failed"; exit 1; }

docker compose -f "$COMPOSE_FILE" cp \
    "${SERVICE_NAME}:/tmp/${SITE_NAME}-files.tar.gz" \
    "${TEMP_DIR}/files.tar.gz" \
    || { log_error "Failed to copy files"; exit 1; }

log_success "Files exported: ${TEMP_DIR}/files.tar.gz"

# ============================================================================
# STEP 2: Create DigitalOcean droplet from template snapshot
# ============================================================================
log_step "Creating DigitalOcean droplet from template..."

DROPLET_NAME="drupalcloud-standalone-${SITE_NAME}"
TEMPLATE_SNAPSHOT_ID="206861760"  # drupal-cloud-template-20251116

# Check if doctl is configured
if ! doctl account get >/dev/null 2>&1; then
    log "Authenticating doctl..."
    doctl auth init --access-token "$DIGITALOCEAN_TOKEN"
fi

# Create droplet from template snapshot (includes LAMP + Drupal pre-installed!)
log "Creating droplet from template snapshot: $DROPLET_NAME..."

# Get all SSH key IDs from the account to ensure we have the right one
ALL_SSH_KEYS=$(doctl compute ssh-key list --format ID --no-header | tr '\n' ',' | sed 's/,$//')
log "Adding all account SSH keys to droplet: $ALL_SSH_KEYS"

# Create droplet with ALL SSH keys to ensure Docker host can connect
doctl compute droplet create "$DROPLET_NAME" \
    --image "$TEMPLATE_SNAPSHOT_ID" \
    --size "$DROPLET_SIZE" \
    --region "$REGION" \
    --ssh-keys "$ALL_SSH_KEYS" \
    --tag-names "drupalcloud,standalone,site-${SITE_NAME}" \
    --wait \
    || { log_error "Droplet creation failed"; exit 1; }

# Get droplet IP
log "Getting droplet IP..."
DROPLET_IP=$(doctl compute droplet list --format Name,PublicIPv4 --no-header | grep "^${DROPLET_NAME}" | awk '{print $2}')

if [ -z "$DROPLET_IP" ]; then
    log_error "Failed to get droplet IP"
    exit 1
fi

log_success "Droplet created from template: $DROPLET_NAME ($DROPLET_IP)"

# Get droplet ID for webhook
DROPLET_ID=$(doctl compute droplet list --format Name,ID --no-header | grep "^${DROPLET_NAME}" | awk '{print $2}')

# ============================================================================
# STEP 3: Wait for droplet to be ready
# ============================================================================
log_step "Waiting for droplet to be ready..."

log "Waiting for SSH to become available..."

# Use the dedicated droplet-access key (DigitalOcean key ID: 52029325)
SSH_KEY="/root/.ssh/droplet-access"
if [ ! -f "$SSH_KEY" ]; then
    log_error "SSH private key not found: $SSH_KEY"
    exit 1
fi

MAX_ATTEMPTS=60
ATTEMPT=0
while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    if ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@"$DROPLET_IP" "echo 'SSH ready'" >/dev/null 2>&1; then
        log_success "SSH is ready"
        break
    fi
    ATTEMPT=$((ATTEMPT + 1))
    echo -n "."
    sleep 5
done
echo ""

if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
    log_error "SSH connection timeout"
    exit 1
fi

# Wait a bit more for cloud-init to finish
log "Waiting for cloud-init to complete..."
sleep 30

# ============================================================================
# STEP 4: Prepare database (template already has LAMP + Drupal)
# ============================================================================
log_step "Preparing database..."

ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no root@"$DROPLET_IP" bash -s <<'REMOTE_DB'
set -e

# Drop and recreate database to ensure clean slate
mysql -e "DROP DATABASE IF EXISTS drupal;"
mysql -e "CREATE DATABASE drupal CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
mysql -e "DROP USER IF EXISTS 'drupal'@'localhost';"
# MariaDB compatible syntax (no WITH clause)
mysql -e "CREATE USER 'drupal'@'localhost' IDENTIFIED BY 'drupal123';"
mysql -e "GRANT ALL PRIVILEGES ON drupal.* TO 'drupal'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

echo "Database prepared"
REMOTE_DB

log_success "Database prepared"

# ============================================================================
# STEP 5: Upload and import database
# ============================================================================
log_step "Uploading and importing database..."

# Upload database dump
log "Uploading database dump..."
scp -i "$SSH_KEY" -o StrictHostKeyChecking=no \
    "${TEMP_DIR}/database.sql.gz" \
    root@"$DROPLET_IP":/tmp/database.sql.gz

# Import database
log "Importing database..."
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no root@"$DROPLET_IP" bash -s <<'REMOTE_IMPORT'
set -e

cd /tmp
gunzip database.sql.gz
mysql drupal < database.sql
rm database.sql

echo "Database imported"
REMOTE_IMPORT

log_success "Database imported"

# ============================================================================
# STEP 6: Upload and extract files
# ============================================================================
log_step "Uploading files..."

# Upload files
scp -i "$SSH_KEY" -o StrictHostKeyChecking=no \
    "${TEMP_DIR}/files.tar.gz" \
    root@"$DROPLET_IP":/tmp/files.tar.gz

# Extract files to template drupalcloud directory
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no root@"$DROPLET_IP" bash -s <<'REMOTE_FILES'
set -e

# Remove old files if they exist
rm -rf /opt/drupalcloud/web/sites/default/files

# Extract new files
cd /opt/drupalcloud/web/sites/default
tar xzf /tmp/files.tar.gz
chown -R www-data:www-data files
chmod -R 755 files
rm /tmp/files.tar.gz

# Ensure private files directory exists
mkdir -p /opt/drupalcloud/private
chown -R www-data:www-data /opt/drupalcloud/private
chmod -R 755 /opt/drupalcloud/private

echo "Files extracted"
REMOTE_FILES

log_success "Files uploaded and extracted"

# ============================================================================
# STEP 7: Configure Drupal settings
# ============================================================================
log_step "Configuring Drupal..."

# Generate random hash salt
HASH_SALT=$(openssl rand -hex 32)

ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no root@"$DROPLET_IP" bash -s "$HASH_SALT" <<'REMOTE_SETTINGS'
set -e

HASH_SALT="$1"

# Create settings.php
cat > /opt/drupalcloud/web/sites/default/settings.php <<EOF
<?php
\$databases['default']['default'] = array (
  'database' => 'drupal',
  'username' => 'drupal',
  'password' => 'drupal123',
  'host' => 'localhost',
  'port' => '3306',
  'driver' => 'mysql',
  'prefix' => '',
  'collation' => 'utf8mb4_unicode_ci',
);

\$settings['hash_salt'] = '${HASH_SALT}';
\$settings['update_free_access'] = FALSE;
\$settings['file_private_path'] = '/opt/drupalcloud/private';
\$settings['config_sync_directory'] = '../config';
\$settings['trusted_host_patterns'] = array(
  '^.*$',
);
EOF

chown www-data:www-data /opt/drupalcloud/web/sites/default/settings.php
chmod 644 /opt/drupalcloud/web/sites/default/settings.php

echo "Settings configured"
REMOTE_SETTINGS

log_success "Drupal configured"

# ============================================================================
# STEP 8: Restart services (Nginx + PHP already configured in template)
# ============================================================================
log_step "Restarting web services..."

ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no root@"$DROPLET_IP" bash -s <<'REMOTE_SERVICES'
set -e

# Restart services to pick up new files/config
systemctl restart php8.3-fpm
systemctl restart nginx

echo "Services restarted"
REMOTE_SERVICES

log_success "Services restarted"

# ============================================================================
# STEP 9: Run Drupal updates
# ============================================================================
log_step "Running Drupal updates..."

ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no root@"$DROPLET_IP" bash -s <<'REMOTE_DRUSH'
set -e

cd /opt/drupalcloud

# Clear cache
sudo -u www-data vendor/bin/drush cache:rebuild

# Run database updates
sudo -u www-data vendor/bin/drush updatedb -y

# Clear cache again
sudo -u www-data vendor/bin/drush cache:rebuild

echo "Drupal updates complete"
REMOTE_DRUSH

log_success "Drupal updates complete"

# ============================================================================
# STEP 10: Cleanup
# ============================================================================
log_step "Cleaning up..."

rm -rf "$TEMP_DIR"
log_success "Temporary files cleaned up"

# ============================================================================
# STEP 11: Send webhook notification
# ============================================================================
log_step "Sending webhook notification..."

# Get webhook URL and token
# Use production dashboard URL if NEXTAUTH_URL is not set or is a preview deployment
if [[ -z "$NEXTAUTH_URL" ]] || [[ "$NEXTAUTH_URL" == *"vercel.app"* ]]; then
  WEBHOOK_URL="https://dashboard.decoupled.io/api/spaces/upgrade-complete"
else
  WEBHOOK_URL="${NEXTAUTH_URL}/api/spaces/upgrade-complete"
fi
WEBHOOK_TOKEN="${INTERNAL_WEBHOOK_TOKEN:-${WEBHOOK_TOKEN:-dev-internal-webhook-token}}"

# Send webhook
# Use subdomain instead of direct IP address for siteUrl
SITE_URL="https://${SITE_NAME}.decoupled.io"

curl -X POST "$WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $WEBHOOK_TOKEN" \
    -d "{
        \"machineName\": \"$SITE_NAME\",
        \"provider\": \"digitalocean\",
        \"dropletId\": \"$DROPLET_ID\",
        \"dropletIp\": \"$DROPLET_IP\",
        \"siteUrl\": \"$SITE_URL\",
        \"region\": \"$REGION\"
    }" \
    || log_warning "Webhook notification failed (non-critical)"

log_success "Webhook sent"

# ============================================================================
# COMPLETION
# ============================================================================
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
MINUTES=$((DURATION / 60))
SECONDS=$((DURATION % 60))

echo ""
echo -e "${GREEN}==================================================================${NC}"
echo -e "${GREEN}✨ Upgrade Complete!${NC}"
echo -e "${GREEN}==================================================================${NC}"
echo -e "  Site: ${CYAN}${SITE_NAME}${NC}"
echo -e "  Droplet ID: ${CYAN}${DROPLET_ID}${NC}"
echo -e "  IP Address: ${CYAN}${DROPLET_IP}${NC}"
echo -e "  URL: ${CYAN}https://${SITE_NAME}.decoupled.io${NC}"
echo -e "  Duration: ${CYAN}${MINUTES}m ${SECONDS}s${NC}"
echo -e "  Method: ${CYAN}Cloned from template snapshot${NC}"
echo -e "${GREEN}==================================================================${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Update DNS: ${SITE_NAME}.decoupled.io -> ${DROPLET_IP}"
echo "  2. Test site: http://${DROPLET_IP}"
echo "  3. (Optional) Configure SSL with certbot"
echo ""
echo -e "${GREEN}Database and files migrated successfully! 🚀${NC}"
echo ""
