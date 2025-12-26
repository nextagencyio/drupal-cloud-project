#!/bin/bash
# Clone a site from a standalone droplet to the shared multisite droplet.
# This script runs on the TARGET (multisite) droplet and pulls data from SOURCE (standalone) droplet.
#
# Usage: SOURCE_IP=<source_ip> SOURCE_SITE=<source_site> TARGET_SITE=<target_site> TARGET_TOKEN=<token> [ADMIN_PASSWORD=<password>] bash clone-from-standalone.sh
#
# Environment variables:
#   SOURCE_IP       - IP address of the standalone droplet to clone from
#   SOURCE_SITE     - Machine name of the site on standalone droplet (usually matches domain)
#   TARGET_SITE     - Machine name for the new multisite site
#   TARGET_TOKEN    - Space token for the new site (space_tok_...)
#   ADMIN_PASSWORD  - Optional admin password to set (defaults to random)
#   DOMAIN_SUFFIX   - Domain suffix for sites (default: decoupled.website)

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

log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
  echo -e "${CYAN}[STEP]${NC} $1"
}

# Check required environment variables
if [ -z "$SOURCE_IP" ] || [ -z "$SOURCE_SITE" ] || [ -z "$TARGET_SITE" ] || [ -z "$TARGET_TOKEN" ]; then
  log_error "Missing required environment variables"
  echo "Usage: SOURCE_IP=<source_ip> SOURCE_SITE=<source_site> TARGET_SITE=<target_site> TARGET_TOKEN=<token> bash clone-from-standalone.sh"
  echo ""
  echo "Required:"
  echo "  SOURCE_IP       - IP of standalone droplet (e.g., 206.81.1.32)"
  echo "  SOURCE_SITE     - Site name on standalone (usually subdomain, e.g., 'bnu0xu7')"
  echo "  TARGET_SITE     - New site name on multisite (e.g., 'xyz123')"
  echo "  TARGET_TOKEN    - Space token (e.g., 'space_tok_abc123...')"
  echo ""
  echo "Optional:"
  echo "  ADMIN_PASSWORD  - Admin password (defaults to random)"
  echo "  DOMAIN_SUFFIX   - Domain suffix (defaults to decoupled.website)"
  exit 1
fi

# Validate token format
if [[ ! "$TARGET_TOKEN" =~ ^space_tok_[0-9a-fA-F]{54}$ ]]; then
  log_error "TARGET_TOKEN format is invalid. Expected: space_tok_[54 hex chars]"
  exit 1
fi

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
TEMP_DIR="/tmp/clone-${SOURCE_SITE}-to-${TARGET_SITE}-${TIMESTAMP}"
DOMAIN_SUFFIX="${DOMAIN_SUFFIX:-decoupled.website}"

# Determine source domain from SOURCE_SITE
# For standalone droplets, the domain is usually subdomain.dcloud.website
SOURCE_DOMAIN="${SOURCE_SITE}.dcloud.website"

log "Starting clone operation"
log "Source: $SOURCE_IP ($SOURCE_DOMAIN)"
log "Target: $TARGET_SITE on multisite droplet"
log "Domain: $DOMAIN_SUFFIX"

mkdir -p "$TEMP_DIR"

# ============================================================================
# STEP 1: Export database and files from standalone droplet
# ============================================================================
log_step "Exporting database and files from standalone droplet..."

# Export database from source standalone droplet
log "Exporting database from standalone droplet..."
ssh -o StrictHostKeyChecking=no root@"$SOURCE_IP" \
  "cd /opt/drupalcloud && \
   docker compose -f docker-compose.prod.yml exec -T drupal \
     /var/www/html/vendor/bin/drush --uri=https://${SOURCE_DOMAIN} \
     sql:dump --gzip --result-file=/tmp/${SOURCE_SITE}.sql" \
  || { log_error "Database export failed"; exit 1; }

# Copy database dump from container to host on source droplet
log "Copying database dump from container to host..."
ssh -o StrictHostKeyChecking=no root@"$SOURCE_IP" \
  "cd /opt/drupalcloud && \
   docker compose -f docker-compose.prod.yml cp drupal:/tmp/${SOURCE_SITE}.sql.gz /tmp/${SOURCE_SITE}.sql.gz" \
  || { log_error "Failed to copy database dump from container"; exit 1; }

# Copy database dump from source to target
log "Copying database dump to multisite droplet..."
scp -o StrictHostKeyChecking=no \
  root@"$SOURCE_IP":/tmp/${SOURCE_SITE}.sql.gz \
  "${TEMP_DIR}/database.sql.gz" \
  || { log_error "Failed to copy database dump"; exit 1; }

log_success "Database exported: ${TEMP_DIR}/database.sql.gz"

# Export files from source standalone droplet
log "Exporting files from standalone droplet..."
ssh -o StrictHostKeyChecking=no root@"$SOURCE_IP" \
  "cd /opt/drupalcloud && \
   docker compose -f docker-compose.prod.yml exec -T drupal \
     tar czf /tmp/${SOURCE_SITE}-files.tar.gz \
     -C /var/www/html/web/sites/default files" \
  || { log_error "Files export failed"; exit 1; }

# Copy files archive from container to host on source droplet
log "Copying files archive from container to host..."
ssh -o StrictHostKeyChecking=no root@"$SOURCE_IP" \
  "cd /opt/drupalcloud && \
   docker compose -f docker-compose.prod.yml cp drupal:/tmp/${SOURCE_SITE}-files.tar.gz /tmp/${SOURCE_SITE}-files.tar.gz" \
  || { log_error "Failed to copy files archive from container"; exit 1; }

# Copy files archive from source to target
log "Copying files archive to multisite droplet..."
scp -o StrictHostKeyChecking=no \
  root@"$SOURCE_IP":/tmp/${SOURCE_SITE}-files.tar.gz \
  "${TEMP_DIR}/files.tar.gz" \
  || { log_error "Failed to copy files"; exit 1; }

log_success "Files exported: ${TEMP_DIR}/files.tar.gz"

# Cleanup source temp files (both in container and on host)
ssh -o StrictHostKeyChecking=no root@"$SOURCE_IP" \
  "cd /opt/drupalcloud && \
   docker compose -f docker-compose.prod.yml exec -T drupal rm -f /tmp/${SOURCE_SITE}.sql.gz /tmp/${SOURCE_SITE}-files.tar.gz && \
   rm -f /tmp/${SOURCE_SITE}.sql.gz /tmp/${SOURCE_SITE}-files.tar.gz" \
  || log_error "Warning: Failed to cleanup source temp files (non-critical)"

# ============================================================================
# STEP 2: Create multisite directory structure on target
# ============================================================================
log_step "Creating multisite directory structure..."

cd /opt/drupalcloud

# Source environment variables
if [ -f .env ]; then
  source .env
fi

SITES_PATH="/var/www/html/web/sites"
TARGET_PATH="${SITES_PATH}/${TARGET_SITE}"

# Create directory structure
log "Creating site directory: $TARGET_PATH"
docker compose -f docker-compose.prod.yml exec -T drupal \
  mkdir -p "${TARGET_PATH}/files" \
  || { log_error "Failed to create site directory"; exit 1; }

log_success "Multisite directory created"

# ============================================================================
# STEP 3: Import database on target multisite
# ============================================================================
log_step "Importing database on target multisite..."

# Generate database name from site name (use site name as db name for multisite)
DB_NAME="${TARGET_SITE}"

# Create database for this multisite
log "Creating database: $DB_NAME"
docker compose -f docker-compose.prod.yml exec -T mysql \
  mariadb -uroot -p"${MYSQL_ROOT_PASSWORD}" \
  -e "DROP DATABASE IF EXISTS \`${DB_NAME}\`;" \
  || { log_error "Failed to drop database"; exit 1; }

docker compose -f docker-compose.prod.yml exec -T mysql \
  mariadb -uroot -p"${MYSQL_ROOT_PASSWORD}" \
  -e "CREATE DATABASE \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" \
  || { log_error "Failed to create database"; exit 1; }

log_success "Database created: $DB_NAME"

# Copy database dump into MySQL container
docker cp "${TEMP_DIR}/database.sql.gz" \
  $(docker compose -f docker-compose.prod.yml ps -q mysql):/tmp/database.sql.gz

# Import database
log "Importing database..."
docker compose -f docker-compose.prod.yml exec -T mysql bash -c \
  "gunzip < /tmp/database.sql.gz | mariadb -uroot -p\${MYSQL_ROOT_PASSWORD} ${DB_NAME}" \
  || { log_error "Database import failed"; exit 1; }

# Cleanup temp file in container
docker compose -f docker-compose.prod.yml exec -T mysql \
  rm -f /tmp/database.sql.gz

log_success "Database imported"

# ============================================================================
# STEP 4: Extract files on target multisite
# ============================================================================
log_step "Extracting files on target multisite..."

# Copy files archive into drupal container
docker cp "${TEMP_DIR}/files.tar.gz" \
  $(docker compose -f docker-compose.prod.yml ps -q drupal):/tmp/files.tar.gz

# Extract files
log "Extracting files..."
docker compose -f docker-compose.prod.yml exec -T drupal bash -c \
  "cd ${TARGET_PATH} && tar xzf /tmp/files.tar.gz" \
  || { log_error "Files extraction failed"; exit 1; }

# Set permissions
docker compose -f docker-compose.prod.yml exec -T drupal \
  chown -R www-data:www-data "${TARGET_PATH}/files" \
  || log_error "Warning: Failed to set permissions (non-critical)"

docker compose -f docker-compose.prod.yml exec -T drupal \
  chmod -R 755 "${TARGET_PATH}/files" \
  || log_error "Warning: Failed to set permissions (non-critical)"

# Cleanup temp file in container
docker compose -f docker-compose.prod.yml exec -T drupal \
  rm -f /tmp/files.tar.gz

log_success "Files extracted and permissions set"

# ============================================================================
# STEP 5: Create Drupal settings.php for multisite
# ============================================================================
log_step "Creating Drupal settings.php..."

# Generate hash salt
HASH_SALT=$(openssl rand -hex 32)

# Create settings.php
cat > /tmp/settings-${TARGET_SITE}.php <<EOF
<?php
\$databases['default']['default'] = array (
  'database' => '${DB_NAME}',
  'username' => 'drupal',
  'password' => '${MYSQL_PASSWORD}',
  'host' => 'mysql',
  'port' => '3306',
  'driver' => 'mysql',
  'prefix' => '',
  'collation' => 'utf8mb4_unicode_ci',
);

\$settings['hash_salt'] = '${HASH_SALT}';
\$settings['update_free_access'] = FALSE;
\$settings['file_private_path'] = '/var/www/html/private/${TARGET_SITE}';
\$settings['config_sync_directory'] = '../config';
\$settings['trusted_host_patterns'] = array(
  '^${TARGET_SITE}\.${DOMAIN_SUFFIX}\$',
  '^.*\.${TARGET_SITE}\.${DOMAIN_SUFFIX}\$',
);
EOF

# Copy settings.php into container
docker cp /tmp/settings-${TARGET_SITE}.php \
  $(docker compose -f docker-compose.prod.yml ps -q drupal):"${TARGET_PATH}/settings.php"

# Set permissions
docker compose -f docker-compose.prod.yml exec -T drupal \
  chown www-data:www-data "${TARGET_PATH}/settings.php"

docker compose -f docker-compose.prod.yml exec -T drupal \
  chmod 644 "${TARGET_PATH}/settings.php"

# Cleanup temp settings file
rm -f /tmp/settings-${TARGET_SITE}.php

log_success "Drupal settings.php created"

# ============================================================================
# STEP 6: Add site to sites.php for multisite routing
# ============================================================================
log_step "Adding site to sites.php..."

SITES_PHP_PATH="/var/www/html/web/sites/sites.php"

# Create sites.php if it doesn't exist
docker compose -f docker-compose.prod.yml exec -T drupal bash -c \
  "if [ ! -f ${SITES_PHP_PATH} ]; then echo '<?php' > ${SITES_PHP_PATH}; fi"

# Add entry to sites.php
docker compose -f docker-compose.prod.yml exec -T drupal bash -c \
  "echo \"\\\$sites['${TARGET_SITE}.${DOMAIN_SUFFIX}'] = '${TARGET_SITE}';\" >> ${SITES_PHP_PATH}"

log_success "Site added to sites.php"

# ============================================================================
# STEP 7: Configure OAuth consumer with space token
# ============================================================================
log_step "Configuring OAuth consumer..."

CONSUMER_UUID=$(uuidgen)
CONSUMER_SECRET=$(openssl rand -hex 32)

# Update OAuth consumer in database (replace existing consumer from source)
# Since we cloned the database, there's likely an existing consumer we need to update
# If the consumers table doesn't exist, skip this step (site may not have Simple OAuth installed)
docker compose -f docker-compose.prod.yml exec -T mysql \
  mariadb -uroot -p"${MYSQL_ROOT_PASSWORD}" "${DB_NAME}" <<SQL 2>/dev/null || true
-- Delete any existing consumers
DELETE FROM consumers WHERE label = 'Dashboard Space Token' OR third_party = 1;

-- Insert new consumer with target token
INSERT INTO consumers (uuid, label, secret, client_id, user_id, third_party, roles)
VALUES (
  '${CONSUMER_UUID}',
  'Dashboard Space Token',
  '${CONSUMER_SECRET}',
  '${TARGET_TOKEN}',
  1,
  1,
  'a:1:{i:0;s:13:"administrator";}'
);
SQL

if [ $? -eq 0 ]; then
  log_success "OAuth consumer configured with token: ${TARGET_TOKEN}"
else
  echo -e "${YELLOW}[WARNING]${NC} Consumers table not found - skipping OAuth configuration"
  echo -e "${YELLOW}[WARNING]${NC} Site may need Simple OAuth module enabled for token authentication"
fi

# ============================================================================
# STEP 8: Set admin password
# ============================================================================
log_step "Setting admin password..."

# Generate random password if not provided
if [ -z "$ADMIN_PASSWORD" ]; then
  ADMIN_PASSWORD=$(openssl rand -base64 12 | tr -d "=+/" | cut -c1-16)
  log "Generated random admin password: $ADMIN_PASSWORD"
fi

docker compose -f docker-compose.prod.yml exec -T drupal \
  /var/www/html/vendor/bin/drush --uri=https://${TARGET_SITE}.${DOMAIN_SUFFIX} \
  user:password admin "$ADMIN_PASSWORD" \
  || log_error "Warning: Failed to set admin password (non-critical)"

log_success "Admin password set: $ADMIN_PASSWORD"

# ============================================================================
# STEP 9: Clear cache and run updates
# ============================================================================
log_step "Running Drupal updates..."

# Clear cache
log "Clearing cache..."
docker compose -f docker-compose.prod.yml exec -T drupal \
  /var/www/html/vendor/bin/drush --uri=https://${TARGET_SITE}.${DOMAIN_SUFFIX} \
  cache:rebuild \
  || log_error "Warning: Cache rebuild failed (non-critical)"

# Run database updates
log "Running database updates..."
docker compose -f docker-compose.prod.yml exec -T drupal \
  /var/www/html/vendor/bin/drush --uri=https://${TARGET_SITE}.${DOMAIN_SUFFIX} \
  updatedb -y \
  || log_error "Warning: Database updates failed (non-critical)"

# Clear cache again
docker compose -f docker-compose.prod.yml exec -T drupal \
  /var/www/html/vendor/bin/drush --uri=https://${TARGET_SITE}.${DOMAIN_SUFFIX} \
  cache:rebuild \
  || log_error "Warning: Cache rebuild failed (non-critical)"

log_success "Drupal updates complete"

# ============================================================================
# STEP 10: Cleanup
# ============================================================================
log_step "Cleaning up..."

rm -rf "$TEMP_DIR"
log_success "Temporary files cleaned up"

# ============================================================================
# STEP 11: Generate one-time login link
# ============================================================================
log_step "Generating one-time login link..."

LOGIN_LINK=$(docker compose -f docker-compose.prod.yml exec -T drupal \
  /var/www/html/vendor/bin/drush --uri=https://${TARGET_SITE}.${DOMAIN_SUFFIX} \
  uli --no-interaction 2>/dev/null || echo "")

if [ -n "$LOGIN_LINK" ]; then
  log_success "One-time login link: $LOGIN_LINK"
fi

# ============================================================================
# COMPLETION
# ============================================================================
echo ""
echo -e "${GREEN}==================================================================${NC}"
echo -e "${GREEN}✨ Clone Complete!${NC}"
echo -e "${GREEN}==================================================================${NC}"
echo -e "  Source: ${CYAN}${SOURCE_DOMAIN} (${SOURCE_IP})${NC}"
echo -e "  Target: ${CYAN}${TARGET_SITE}.${DOMAIN_SUFFIX}${NC}"
echo -e "  Database: ${CYAN}${DB_NAME}${NC}"
echo -e "  Token: ${CYAN}${TARGET_TOKEN}${NC}"
echo -e "  Admin Password: ${CYAN}${ADMIN_PASSWORD}${NC}"
if [ -n "$LOGIN_LINK" ]; then
  echo -e "  Login Link: ${CYAN}${LOGIN_LINK}${NC}"
fi
echo -e "${GREEN}==================================================================${NC}"
echo ""
echo -e "${GREEN}Site cloned from standalone to multisite successfully! 🚀${NC}"
echo ""
