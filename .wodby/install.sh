#!/bin/bash
set -e

echo "=================================================="
echo "Drupal Cloud Installation Script"
echo "=================================================="

# Change to web root
cd web

# Check if Drupal is already installed
if drush status bootstrap 2>/dev/null | grep -q "Successful"; then
  echo "Drupal already installed, skipping installation"
  echo "To force reinstall, run: drush sql:drop -y"
  exit 0
fi

# Install Drupal
echo "Installing Drupal..."
drush site:install --account-name=admin --account-pass="${DRUPAL_ADMIN_PASSWORD:-admin}" --account-mail="${DRUPAL_ADMIN_EMAIL:-admin@example.com}" --site-name="Drupal Cloud Site" --site-mail="${DRUPAL_SITE_EMAIL:-noreply@example.com}" --yes

# Apply recipes in correct order
echo "Applying dcloud-admin recipe..."
drush recipe ../recipes/dcloud-admin

echo "Applying dcloud-api recipe..."
drush recipe ../recipes/dcloud-api

echo "Applying dcloud-fields recipe..."
drush recipe ../recipes/dcloud-fields

echo "Applying dcloud-core recipe..."
drush recipe ../recipes/dcloud-core

echo "Applying dcloud-content recipe..."
drush recipe ../recipes/dcloud-content

# Setup OAuth consumers
echo "Setting up OAuth consumers..."
drush scr ../scripts/consumers-next.php || echo "⚠️  OAuth setup failed"

# Clear cache
echo "Clearing cache..."
drush cache:rebuild

echo "=================================================="
echo "✅ Drupal Cloud installation completed!"
echo "=================================================="
