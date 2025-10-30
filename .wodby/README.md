# Wodby Deployment Configuration

This directory contains configuration files for deploying Drupal Cloud on Wodby.

## Files

- **`wodby.yml`** - Main deployment pipeline configuration
- **`install.sh`** - Installation script for fresh Drupal Cloud deployments

## Deployment Pipeline

The `wodby.yml` file defines the post-deployment pipeline that runs after each deployment:

### Pipeline Stages

1. **Install Composer dependencies** - Runs `composer install`
2. **Check installation status** - Determines if Drupal is already installed
3. **Install Drupal site** - Installs Drupal with all recipes (dev/stage only)
4. **Import configuration** - Imports config from `config/` directory (prod only)
5. **Run database updates** - Applies any pending database updates
6. **Clear cache** - Rebuilds Drupal cache
7. **Set file permissions** - Ensures correct permissions on files directory

### Environment-Specific Behavior

- **Dev/Stage environments**: Fresh install with recipes
- **Production environment**: Config import only (no fresh install)

## Environment Variables

You can set these environment variables in Wodby:

- `DRUPAL_ADMIN_PASSWORD` - Admin user password (default: admin)
- `DRUPAL_ADMIN_EMAIL` - Admin user email (default: admin@example.com)
- `DRUPAL_SITE_EMAIL` - Site email address (default: noreply@example.com)

## Wodby Environment Variables

The pipeline uses these Wodby-provided variables:

- `$APP_ROOT` - Application root directory
- `$HTTP_ROOT` - Web root directory (typically `/app/web`)
- `$WODBY_ENVIRONMENT_TYPE` - Environment type (dev, stage, prod)

## Manual Installation

If you need to manually install Drupal Cloud, you can run:

```bash
cd $HTTP_ROOT
bash ../.wodby/install.sh
```

## Configuration Sync Directory

Configuration files are stored in `config/` directory at the project root, configured in `settings.pantheon.php`:

```php
$settings['config_sync_directory'] = '../config';
```

## OAuth Consumers

OAuth consumers for Next.js integration are automatically created during installation via `scripts/consumers-next.php`.

## Troubleshooting

### Installation fails
- Check logs in Wodby dashboard under Instance > Tasks
- Verify all recipes are present in `/recipes/` directory
- Ensure Drush 13+ is available

### Cache rebuild fails
- This may happen on first deployment
- Manually run: `drush cache:rebuild` from the web root

### Permission errors
- File permissions are set in the pipeline
- If issues persist, check Wodby container user permissions

## Support

For Wodby-specific issues, consult:
- [Wodby Documentation](https://wodby.com/docs/)
- [Wodby Drupal Stack](https://wodby.com/stacks/drupal11)
