#!/bin/bash

# DrupalCloud Growth Plan Upgrade Script
# Migrates a Starter space (multisite) to Growth plan (Upsun)
# Usage: ./scripts/host/growth/upgrade-to-growth.sh <site-machine-name>

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

# Show usage
show_usage() {
    echo "Usage: $0 <site-machine-name>"
    echo ""
    echo "Upgrades a Starter space to Growth plan (Upsun)"
    echo ""
    echo "Arguments:"
    echo "  site-machine-name  Machine name of the space to upgrade (e.g., 'my-site')"
    echo ""
    echo "Examples:"
    echo "  $0 my-site         # Upgrade 'my-site' to Growth plan"
    echo ""
    echo "Prerequisites:"
    echo "  - Upsun CLI installed and authenticated"
    echo "  - Site must exist in multisite"
    echo "  - MySQL access to drupalcloud database"
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
if [[ $# -ne 1 ]]; then
    log_error "Invalid number of arguments"
    show_usage
    exit 1
fi

SITE_NAME="$1"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
EXPORT_DIR="/tmp/dcloud-upgrade-${SITE_NAME}-${TIMESTAMP}"
PROJECT_NAME="dcloud-${SITE_NAME}"

# Detect environment: production vs local Docker
if [[ -d "/opt/drupalcloud" ]] && [[ ! -d "/Users" ]]; then
    # Production environment (running on server with Docker)
    MULTISITE_DIR="/var/www/html/web/sites/${SITE_NAME}"
    DRUPAL_WEB_DIR="/var/www/html/web"
    DOCKER_CONTAINER="drupal-web"
    DOCKER_EXEC="docker exec drupal-web"
    IS_PRODUCTION=true
    DOMAIN_SUFFIX="decoupled.io"
else
    # Local development (Mac/Linux with Docker)
    MULTISITE_DIR="/var/www/html/web/sites/${SITE_NAME}"
    DRUPAL_WEB_DIR="/var/www/html/web"
    DOCKER_CONTAINER="drupal-web-local"
    DOCKER_EXEC="docker exec drupal-web-local"
    IS_PRODUCTION=false
    DOMAIN_SUFFIX="localhost"
fi

DB_PREFIX="${SITE_NAME}_"

# Upsun configuration (Growth plan)
UPSUN_REGION="us-2.platform.sh"
# Use environment variable or fallback to default org ID
# For local development, set UPSUN_ORG_ID in .env.local
UPSUN_ORGANIZATION="${UPSUN_ORG_ID:-01k8tv1wv5t608z3cz68yeb3jd}" # Default: Jay's org

# Determine template directory path
# The Drupal template with Upsun configuration
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
TEMPLATE_DIR="/tmp/dcloud-template-${SITE_NAME}"
TEMPLATE_REPO_URL="git@github.com:nextagencyio/drupal-cloud-docker.git"
TEMPLATE_BRANCH="main"

log "========================================="
log "DrupalCloud Growth Plan Upgrade"
log "========================================="
log "Site: $SITE_NAME"
log "Timestamp: $TIMESTAMP"
log "Export directory: $EXPORT_DIR"
log "========================================="

# Validate prerequisites
validate_prerequisites

# Step 1: Verify site exists in multisite
log_step "1/7 Verifying site exists in multisite..."

if [[ -n "$DOCKER_EXEC" ]]; then
    # Check inside Docker container
    if ! $DOCKER_EXEC test -d "$MULTISITE_DIR"; then
        log_error "Site directory not found in Docker: $MULTISITE_DIR"
        log "Make sure the site exists in the multisite"
        exit 1
    fi
else
    # Check on host machine (production)
    if [[ ! -d "$MULTISITE_DIR" ]]; then
        log_error "Site directory not found: $MULTISITE_DIR"
        log "Make sure the site exists in the multisite"
        exit 1
    fi
fi

log_success "Site found in multisite"

# Step 1.5: Fix database host in settings.php if needed
log_step "1.5/7 Verifying database configuration..."

SETTINGS_FILE="$MULTISITE_DIR/settings.php"

if [[ -n "$DOCKER_EXEC" ]]; then
    # Check and fix in Docker container
    if $DOCKER_EXEC grep -q "'host' => 'mysql-local'" "$SETTINGS_FILE" 2>/dev/null; then
        log_warning "Found incorrect database host 'mysql-local', fixing to 'mysql'..."
        $DOCKER_EXEC sed -i "s/'host' => 'mysql-local'/'host' => 'mysql'/g" "$SETTINGS_FILE"
        log_success "Database host fixed in settings.php"
    else
        log_success "Database configuration is correct"
    fi
else
    # Check and fix on host machine (production)
    if grep -q "'host' => 'mysql-local'" "$SETTINGS_FILE" 2>/dev/null; then
        log_warning "Found incorrect database host 'mysql-local', fixing to 'mysql'..."
        sed -i "s/'host' => 'mysql-local'/'host' => 'mysql'/g" "$SETTINGS_FILE"
        log_success "Database host fixed in settings.php"
    else
        log_success "Database configuration is correct"
    fi
fi

# Step 2: Export database from multisite
log_step "2/7 Exporting database from multisite..."

mkdir -p "$EXPORT_DIR"
DB_FILE="$EXPORT_DIR/database.sql"

# Export database using drush from the multisite
if [[ -n "$DOCKER_EXEC" ]]; then
    # Export from Docker container using --uri with correct domain suffix
    $DOCKER_EXEC bash -c "cd $DRUPAL_WEB_DIR && ../vendor/bin/drush --uri=${SITE_NAME}.${DOMAIN_SUFFIX} sql:dump" > "$DB_FILE"
else
    # Export on host machine (production) using --uri to avoid drush alias issues
    cd "$DRUPAL_WEB_DIR"
    ../vendor/bin/drush --uri=${SITE_NAME}.${DOMAIN_SUFFIX} sql:dump --result-file="$DB_FILE"
fi

if [[ ! -f "$DB_FILE" ]]; then
    log_error "Database export failed"
    exit 1
fi

DB_SIZE=$(du -h "$DB_FILE" | cut -f1)
log_success "Database exported ($DB_SIZE)"

# Step 3: Export files from multisite
log_step "3/7 Exporting files from multisite..."

FILES_DIR="$MULTISITE_DIR/files"
FILES_ARCHIVE="$EXPORT_DIR/files.tar.gz"

if [[ -n "$DOCKER_EXEC" ]]; then
    # Check and export files from Docker container
    if $DOCKER_EXEC test -d "$FILES_DIR"; then
        $DOCKER_EXEC tar -czf /tmp/files.tar.gz -C "$MULTISITE_DIR" files
        docker cp ${DOCKER_CONTAINER}:/tmp/files.tar.gz "$FILES_ARCHIVE"
        $DOCKER_EXEC rm /tmp/files.tar.gz
        FILES_SIZE=$(du -h "$FILES_ARCHIVE" | cut -f1)
        log_success "Files exported ($FILES_SIZE)"
    else
        log_warning "No files directory found, skipping files export"
        touch "$FILES_ARCHIVE" # Create empty archive
    fi
else
    # Export files on host machine (production)
    if [[ -d "$FILES_DIR" ]]; then
        tar -czf "$FILES_ARCHIVE" -C "$MULTISITE_DIR" files
        FILES_SIZE=$(du -h "$FILES_ARCHIVE" | cut -f1)
        log_success "Files exported ($FILES_SIZE)"
    else
        log_warning "No files directory found, skipping files export"
        touch "$FILES_ARCHIVE" # Create empty archive
    fi
fi

# Step 4: Create Upsun project
log_step "4/7 Creating Upsun project..."
log "Project name: $PROJECT_NAME"
log "Region: $UPSUN_REGION"
log "Organization: $UPSUN_ORGANIZATION"

# Create a temporary file for the output
UPSUN_OUTPUT_FILE="$EXPORT_DIR/upsun-create-output.log"

# Create project with timeout
log "Executing: upsun project:create --title=\"$PROJECT_NAME\" --region=\"$UPSUN_REGION\" --org=\"$UPSUN_ORGANIZATION\" --no-interaction"
set +e # Don't exit on error

# Run with timeout (works on both Linux and macOS)
if command -v timeout &> /dev/null; then
    # Linux timeout command
    timeout 120 upsun project:create \
        --title="$PROJECT_NAME" \
        --region="$UPSUN_REGION" \
        --org="$UPSUN_ORGANIZATION" \
        --no-interaction > "$UPSUN_OUTPUT_FILE" 2>&1 &
    UPSUN_PID=$!
else
    # macOS fallback - run in background and kill after timeout
    upsun project:create \
        --title="$PROJECT_NAME" \
        --region="$UPSUN_REGION" \
        --org="$UPSUN_ORGANIZATION" \
        --no-interaction > "$UPSUN_OUTPUT_FILE" 2>&1 &
    UPSUN_PID=$!

    # Wait for process with timeout
    WAIT_TIME=0
    MAX_WAIT=120
    while kill -0 $UPSUN_PID 2>/dev/null && [ $WAIT_TIME -lt $MAX_WAIT ]; do
        sleep 1
        WAIT_TIME=$((WAIT_TIME + 1))
    done

    # Kill if still running
    if kill -0 $UPSUN_PID 2>/dev/null; then
        kill -9 $UPSUN_PID 2>/dev/null
        UPSUN_EXIT_CODE=124 # Timeout exit code
    fi
fi

# Wait for process to complete
wait $UPSUN_PID 2>/dev/null
UPSUN_EXIT_CODE=$?
set -e

# Log the full output
log "Upsun CLI output:"
cat "$UPSUN_OUTPUT_FILE"

# Check exit code
if [[ $UPSUN_EXIT_CODE -eq 124 ]]; then
    log_error "Upsun project creation timed out after 120 seconds"
    log_error "This might indicate:"
    log_error "  - Network connectivity issues"
    log_error "  - Upsun API is slow or unavailable"
    log_error "  - Authentication issues"
    exit 1
elif [[ $UPSUN_EXIT_CODE -ne 0 ]]; then
    log_error "Upsun project creation failed with exit code: $UPSUN_EXIT_CODE"

    # Check for common error patterns
    if grep -qi "trial\|limit\|quota" "$UPSUN_OUTPUT_FILE"; then
        log_error "It appears you've reached your trial/quota limit"
        log_error "You may need to upgrade your Upsun account or delete existing projects"
    elif grep -qi "authentication\|unauthorized\|login" "$UPSUN_OUTPUT_FILE"; then
        log_error "Authentication failed. Try running: upsun auth:logout && upsun auth:login"
    elif grep -qi "organization.*not found" "$UPSUN_OUTPUT_FILE"; then
        log_error "Organization '$UPSUN_ORGANIZATION' not found"
        log_error "Available organizations:"
        upsun organization:list 2>&1 || log_error "Could not list organizations"
    fi

    exit 1
fi

# Read the output
UPSUN_OUTPUT=$(cat "$UPSUN_OUTPUT_FILE")

# Extract project ID from output (try multiple patterns)
# Note: macOS grep doesn't support -P, so we use basic grep with sed/awk
PROJECT_ID=$(echo "$UPSUN_OUTPUT" | grep -o "Project ID: [a-z0-9]*" | awk '{print $3}' || \
             echo "$UPSUN_OUTPUT" | grep -o "^[a-z0-9]\{13\}$" | head -1 || \
             echo "")

if [[ -z "$PROJECT_ID" ]]; then
    log_error "Could not extract project ID from Upsun output"
    log_error "Expected format: 'Project ID: <id>' but output was:"
    log_error "---"
    echo "$UPSUN_OUTPUT"
    log_error "---"
    exit 1
fi

log_success "Upsun project created successfully!"
log "Project ID: $PROJECT_ID"
log "Project name: $PROJECT_NAME"

# Step 5: Push code to Upsun and wait for deployment
log_step "5/7 Deploying Drupal to Upsun..."

# Clone the Drupal template repository
log "Cloning Drupal template repository..."
log "Repository: $TEMPLATE_REPO_URL"
log "Branch: $TEMPLATE_BRANCH"

if [[ -d "$TEMPLATE_DIR" ]]; then
    log "Removing existing template directory..."
    rm -rf "$TEMPLATE_DIR"
fi

git clone --branch "$TEMPLATE_BRANCH" "$TEMPLATE_REPO_URL" "$TEMPLATE_DIR"

if [[ ! -d "$TEMPLATE_DIR/.upsun" ]]; then
    log_error "Template cloned but .upsun directory not found"
    log_error "The repository may not have Upsun configuration on branch: $TEMPLATE_BRANCH"
    exit 1
fi

log_success "Template cloned successfully"

# Set up git remote for the new project
log "Setting up git repository..."
log "Template directory: $TEMPLATE_DIR"

cd "$TEMPLATE_DIR"

# Check if remote already exists
if git remote | grep -q "upsun-${SITE_NAME}"; then
    log "Removing existing remote: upsun-${SITE_NAME}"
    git remote remove "upsun-${SITE_NAME}"
fi

# Add upsun remote
GIT_REMOTE="${PROJECT_ID}@git.${UPSUN_REGION}:${PROJECT_ID}.git"
log "Adding git remote: $GIT_REMOTE"
git remote add "upsun-${SITE_NAME}" "$GIT_REMOTE"

# Push to Upsun using CLI (handles SSH authentication automatically)
log "Pushing code to Upsun main branch (this will take 5-7 minutes)..."
set +e
upsun push -p "$PROJECT_ID" --target main --yes --force 2>&1 | tee "$EXPORT_DIR/git-push.log"
GIT_PUSH_EXIT=$?
set -e

if [[ $GIT_PUSH_EXIT -ne 0 ]]; then
    log_error "Git push failed with exit code: $GIT_PUSH_EXIT"
    log_error "Check $EXPORT_DIR/git-push.log for details"
    exit 1
fi

log_success "Code pushed successfully"

# Wait for deployment to complete
log "Waiting for initial deployment (Drupal install + recipes)..."
sleep 10 # Give it a moment to start

# Poll for deployment status
log "Polling for deployment status (max wait: 10 minutes)..."
MAX_WAIT=600 # 10 minutes
WAITED=0
while [[ $WAITED -lt $MAX_WAIT ]]; do
    set +e
    STATUS=$(upsun environment:info -p "$PROJECT_ID" -e main status --no-wait 2>&1)
    STATUS_EXIT=$?
    set -e

    if [[ $STATUS_EXIT -eq 0 ]] && echo "$STATUS" | grep -q "active"; then
        log_success "Deployment completed"
        break
    fi

    log "Deployment in progress... (${WAITED}s / ${MAX_WAIT}s)"
    sleep 30
    WAITED=$((WAITED + 30))
done

if [[ $WAITED -ge $MAX_WAIT ]]; then
    log_error "Deployment timeout after ${MAX_WAIT} seconds"
    log_error "The deployment may still be running on Upsun"
    log_error "Check status with: upsun environment:info -p $PROJECT_ID -e main"
    exit 1
fi

# Get the Upsun site URL
log "Retrieving Upsun site URL..."
set +e
UPSUN_URL=$(upsun url -p "$PROJECT_ID" -e main 2>&1 | grep -o "https://[^[:space:]]*" | head -1)
URL_EXIT=$?
set -e

if [[ $URL_EXIT -ne 0 ]] || [[ -z "$UPSUN_URL" ]]; then
    log_warning "Could not retrieve Upsun URL automatically"
    UPSUN_URL="https://console.upsun.com/projects/$PROJECT_ID"
fi

log_success "Upsun site deployed"
log "Site URL: $UPSUN_URL"

# Step 6: Import database to Upsun
log_step "6/7 Importing database to Upsun..."

# Check database file exists and has content
if [[ ! -f "$DB_FILE" ]]; then
    log_error "Database file not found: $DB_FILE"
    exit 1
fi

DB_SIZE=$(du -h "$DB_FILE" | cut -f1)
log "Database file: $DB_FILE ($DB_SIZE)"

# Upload database file
log "Uploading database file to Upsun..."
set +e
upsun ssh -p "$PROJECT_ID" -e main "cat > /tmp/database.sql" < "$DB_FILE" 2>&1 | tee "$EXPORT_DIR/db-upload.log"
UPLOAD_EXIT=$?
set -e

if [[ $UPLOAD_EXIT -ne 0 ]]; then
    log_error "Database upload failed with exit code: $UPLOAD_EXIT"
    log_error "Check $EXPORT_DIR/db-upload.log for details"
    exit 1
fi

log_success "Database file uploaded"

# Import database via drush
log "Importing database via Drush (this may take a few minutes)..."
set +e
upsun ssh -p "$PROJECT_ID" -e main "cd web && ../vendor/bin/drush sql:cli < /tmp/database.sql" 2>&1 | tee "$EXPORT_DIR/db-import.log"
IMPORT_EXIT=$?
set -e

if [[ $IMPORT_EXIT -ne 0 ]]; then
    log_error "Database import failed with exit code: $IMPORT_EXIT"
    log_error "Check $EXPORT_DIR/db-import.log for details"
    exit 1
fi

log_success "Database imported successfully"

# Clean up temp file
log "Cleaning up temporary database file..."
upsun ssh -p "$PROJECT_ID" -e main "rm -f /tmp/database.sql" 2>&1 || log_warning "Could not remove temp database file"

log_success "Database import completed"

# Step 7: Import files to Upsun
log_step "7/7 Importing files to Upsun..."

if [[ -s "$FILES_ARCHIVE" ]]; then
    FILES_SIZE=$(du -h "$FILES_ARCHIVE" | cut -f1)
    log "Files archive: $FILES_ARCHIVE ($FILES_SIZE)"

    # Upload files using mount:upload
    log "Uploading files to Upsun..."
    set +e
    upsun mount:upload -p "$PROJECT_ID" -e main \
        --source="$FILES_ARCHIVE" \
        --mount="web/sites/default/files" \
        --no-interaction 2>&1 | tee "$EXPORT_DIR/files-upload.log"
    FILES_EXIT=$?
    set -e

    if [[ $FILES_EXIT -ne 0 ]]; then
        log_error "Files upload failed with exit code: $FILES_EXIT"
        log_error "Check $EXPORT_DIR/files-upload.log for details"
        exit 1
    fi

    log_success "Files imported successfully"
else
    log_warning "No files to import (empty or missing archive)"
fi

# Clear cache
log "Clearing Drupal cache..."
set +e
upsun ssh -p "$PROJECT_ID" -e main "cd web && ../vendor/bin/drush cr" 2>&1 | tee "$EXPORT_DIR/cache-clear.log"
CACHE_EXIT=$?
set -e

if [[ $CACHE_EXIT -ne 0 ]]; then
    log_warning "Cache clear failed (exit code: $CACHE_EXIT)"
    log_warning "You may need to clear cache manually"
else
    log_success "Cache cleared"
fi

# Final verification
log_step "Verifying deployment..."
set +e
upsun ssh -p "$PROJECT_ID" -e main "cd web && ../vendor/bin/drush status" 2>&1 | tee "$EXPORT_DIR/drush-status.log"
STATUS_CHECK_EXIT=$?
set -e

if [[ $STATUS_CHECK_EXIT -eq 0 ]]; then
    log_success "Drupal is running correctly"
else
    log_warning "Could not verify Drupal status (exit code: $STATUS_CHECK_EXIT)"
    log_warning "Check $EXPORT_DIR/drush-status.log for details"
fi

# Clean up export directory
log "Cleaning up temporary files..."
log "Export data saved in: $EXPORT_DIR"
log "You can delete this directory after verifying the upgrade"
# Don't delete yet - keep for troubleshooting
# rm -rf "$EXPORT_DIR"

# Display summary
log "========================================="
log_success "Growth Plan Upgrade Complete!"
log "========================================="
log "Site: $SITE_NAME"
log "Upsun Project ID: $PROJECT_ID"
log "Upsun Project Name: $PROJECT_NAME"
log "Upsun URL: $UPSUN_URL"
log "Region: $UPSUN_REGION"
log "========================================="

# Notify API that upgrade is complete with retry logic
log ""
log "Updating space record in dashboard..."

# Get environment variables (should be loaded from .env.local in production)
WEBHOOK_URL="${NEXTAUTH_URL:-http://localhost:3333}/api/spaces/upgrade-complete"
WEBHOOK_TOKEN="${INTERNAL_WEBHOOK_TOKEN:-${WEBHOOK_TOKEN:-dev-internal-webhook-token}}"

# Function to call webhook
call_webhook() {
  curl -X POST "$WEBHOOK_URL" \
    -H "Authorization: Bearer $WEBHOOK_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
      \"machineName\": \"$SITE_NAME\",
      \"projectId\": \"$PROJECT_ID\",
      \"projectName\": \"$PROJECT_NAME\",
      \"projectUrl\": \"$UPSUN_URL\",
      \"region\": \"$UPSUN_REGION\"
    }" \
    --silent \
    --show-error \
    --max-time 30 2>&1
}

# Retry logic with exponential backoff
MAX_RETRIES=5
RETRY_COUNT=0
WEBHOOK_SUCCESS=false

set +e
while [[ $RETRY_COUNT -lt $MAX_RETRIES ]]; do
  if [[ $RETRY_COUNT -gt 0 ]]; then
    # Exponential backoff: 2, 4, 8, 16 seconds
    WAIT_TIME=$((2 ** RETRY_COUNT))
    log "Retrying in ${WAIT_TIME} seconds (attempt $((RETRY_COUNT + 1))/$MAX_RETRIES)..."
    sleep $WAIT_TIME
  fi

  WEBHOOK_RESPONSE=$(call_webhook)
  WEBHOOK_EXIT=$?

  if [[ $WEBHOOK_EXIT -eq 0 ]] && echo "$WEBHOOK_RESPONSE" | grep -q "\"success\":true"; then
    log_success "Dashboard updated successfully"
    WEBHOOK_SUCCESS=true
    break
  else
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [[ $RETRY_COUNT -lt $MAX_RETRIES ]]; then
      log_warning "Webhook attempt $RETRY_COUNT failed: $WEBHOOK_RESPONSE"
    fi
  fi
done
set -e

if [[ "$WEBHOOK_SUCCESS" != "true" ]]; then
  log_warning "Failed to update dashboard after $MAX_RETRIES attempts"
  log_warning "Final response: $WEBHOOK_RESPONSE"
  log ""
  log "Manual update required:"
  log "Run: node scripts/complete-upgrade.js $SITE_NAME $PROJECT_ID $UPSUN_URL"
  log ""
  log "Or update database directly:"
  log "   UPDATE spaces SET "
  log "     hosting_type='growth',"
  log "     growth_project_id='$PROJECT_ID',"
  log "     growth_project_name='$PROJECT_NAME',"
  log "     growth_region='$UPSUN_REGION',"
  log "     drupal_site_url='$UPSUN_URL'"
  log "   WHERE machine_name='$SITE_NAME';"
fi

log ""
log "Next steps:"
log "1. Test the site: $UPSUN_URL"
log "2. Update DNS to point to Upsun"
log ""
log_warning "Note: This is a permanent upgrade. The space cannot be downgraded."

# Create success marker file for GitHub Actions workflow
touch "/tmp/upgrade-${SITE_NAME}-success"
