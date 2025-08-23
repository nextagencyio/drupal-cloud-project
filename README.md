# Drupal Cloud Backend Template

This is the Drupal 11 multisite backend template for the Drupal Cloud project. It provides a headless CMS with GraphQL API, OAuth authentication, and multisite capabilities for creating and managing individual Drupal sites.

## Overview

This template serves as the backend API for the Drupal Cloud dashboard, enabling:

- **Multisite Architecture**: Each "space" gets its own Drupal site with separate database
- **GraphQL API**: Headless CMS capabilities with GraphQL Compose
- **OAuth Integration**: Simple OAuth for secure API authentication
- **DDEV Development**: Local development environment with wildcard subdomains

## Key Features

- **Drupal 11**: Latest Drupal version with modern PHP 8.3
- **GraphQL Compose**: Automatic GraphQL schema generation
- **Simple OAuth**: API authentication for headless applications
- **Admin Toolbar**: Enhanced admin experience with Gin theme
- **Paragraphs**: Flexible content modeling
- **Pathauto**: Automatic URL alias generation
- **Multisite Ready**: Configured for wildcard subdomain support
- **Custom Modules**: Enhanced functionality with dcloud-specific modules
- **SQLite Support**: Lightweight database per space for portability
- **Usage Tracking**: Built-in API request and content usage monitoring

## Architecture

```
├── .ddev/                    # DDEV configuration
│   ├── config.yaml          # Main DDEV settings
│   ├── nginx_full/          # Custom nginx configuration
│   └── commands/            # Custom DDEV commands
├── web/                     # Drupal web root
│   ├── sites/               # Multisite configurations
│   │   ├── default/         # Default site
│   │   └── sites.php        # Multisite routing
│   ├── modules/custom/      # Custom modules
│   └── themes/custom/       # Custom themes
├── config/                  # Configuration management
├── scripts/                 # Deployment and utility scripts
└── composer.json           # Dependencies and project metadata
```

## Quick Start

### Prerequisites

- [DDEV](https://ddev.readthedocs.io/en/stable/users/install/) installed
- Docker and Docker Compose
- PHP 8.3+ (for local development outside DDEV)

### Local Development Setup

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd <repository-name>
   ```

2. **Start DDEV**
   ```bash
   ddev start
   ```

3. **Install dependencies**
   ```bash
   ddev composer install
   ```

4. **Install Drupal**
   ```bash
   ddev install
   ```
   This custom command installs Drupal with default settings, enables all essential modules (including custom dcloud modules), and configures the Gin admin theme.

5. **Access the site**
   - Main site: https://dcloud.ddev.site
   - Admin: https://dcloud.ddev.site/user/login

### Multisite Development

The template is configured for wildcard subdomains (`*.dcloud.ddev.site`), allowing you to create new sites:

```bash
# Create a new site
ddev drush site:install --uri=https://mysite.dcloud.ddev.site

# Access the new site
# https://mysite.dcloud.ddev.site
```

## Key Dependencies

### Core Drupal Modules
- **drupal/core-recommended**: Drupal 11.2+ core
- **drupal/admin_toolbar**: Enhanced admin interface
- **drupal/gin**: Modern admin theme
- **drupal/gin_login**: Styled login pages

### Headless/API Modules
- **drupal/graphql**: GraphQL API foundation
- **drupal/graphql_compose**: Automatic schema generation
- **drupal/simple_oauth**: OAuth 2.0 authentication
- **drupal/decoupled_preview_iframe**: Preview support for headless

### Content Management
- **drupal/paragraphs**: Flexible content components
- **drupal/field_group**: Organize form fields
- **drupal/pathauto**: Automatic URL aliases

### Custom Modules
- **dcloud_chatbot**: AI-powered content generation and assistance
- **dcloud_config**: Space configuration and setup wizards
- **dcloud_import**: Content import/export functionality
- **dcloud_revalidate**: Next.js revalidation integration
- **dcloud_usage**: Usage statistics and API request tracking
- **dcloud_user_redirect**: User authentication and redirection

### Development Tools
- **drush/drush**: Command-line interface
- **cweagans/composer-patches**: Apply patches via Composer

### Custom DDEV Commands
- **ddev install**: Install Drupal with default settings, enable all modules, and configure Gin theme

## Configuration

### DDEV Settings

The `.ddev/config.yaml` includes:

- **Project Type**: `drupal11`
- **PHP Version**: `8.3`
- **Database**: MariaDB 10.11 (local), SQLite (per space in production)
- **Webserver**: nginx-fpm
- **Wildcard Domains**: `*.dcloud.ddev.site`

### Multisite Configuration

Sites are configured in `web/sites/sites.php` with automatic routing based on subdomain patterns.

### GraphQL Setup

GraphQL endpoints are available at:
- Schema: `/graphql/explorer`
- API: `/graphql`

### OAuth Configuration

Simple OAuth provides API authentication for the Next.js dashboard to communicate securely with Drupal.

### Custom Module APIs

Each custom module provides specific functionality:

- **dcloud_usage**: `/api/dcloud/usage` - Real-time usage statistics
- **dcloud_chatbot**: `/api/chatbot/*` - AI-powered content assistance
- **dcloud_import**: `/api/dcloud-import` - Content import/export
- **dcloud_revalidate**: Integration with Next.js revalidation

## Development Workflow

### Creating New Sites

```bash
# Method 1: Using Drush
ddev drush site:install --uri=https://sitename.dcloud.ddev.site

# Method 2: Via Dashboard
# Use the Drupal Cloud dashboard interface to create and manage spaces
```

### Database Management

```bash
# Export database
ddev export-db --file=backup.sql.gz

# Import database
ddev import-db --file=backup.sql.gz

# Access database
ddev mysql
```

### Custom Module Development

```bash
# Generate a new module
ddev drush generate module

# Enable custom modules
ddev drush en custom_module_name
```

### Configuration Management

```bash
# Export configuration
ddev drush config:export

# Import configuration
ddev drush config:import

# Check configuration status
ddev drush config:status
```

## Site Management

Site management is handled through the Drupal Cloud dashboard interface, which provides:

- Automated site creation and provisioning
- Space cloning with conflict resolution
- Real-time status updates and monitoring  
- Usage statistics and analytics
- Archive/unarchive functionality

### GraphQL API

- **Endpoint**: `/graphql`
- **Explorer**: `/graphql/explorer`
- **Schema**: Auto-generated from content types

### OAuth Authentication

- **Token Endpoint**: `/oauth/token`
- **Authorization**: Bearer token authentication
- **Scopes**: Configurable access levels

## Deployment

### Production Requirements

- PHP 8.3+ with required extensions (including SQLite)
- Web server (Nginx or Apache) with SSL
- Composer 2.x
- Drush 13.x
- SQLite support for individual space databases

### Environment Variables

```bash
# Database (SQLite paths are managed automatically per space)
DATABASE_URL=sqlite://path/to/space.sqlite

# OAuth
OAUTH_CLIENT_ID=your-client-id
OAUTH_CLIENT_SECRET=your-client-secret

# API Keys
API_KEY=your-secure-api-key

# Custom Module Settings
CHATBOT_API_KEY=your-chatbot-api-key
REVALIDATE_SECRET=your-revalidation-secret
```

### Deployment Steps

1. **Deploy template to server**
   ```bash
   # Template is deployed as part of the Drupal Cloud automation
   ```

2. **Install dependencies**
   ```bash
   composer install --no-dev --optimize-autoloader
   ```

3. **Configure settings**
   ```bash
   cp web/sites/default/default.settings.php web/sites/default/settings.php
   # Edit settings.php with production values
   ```

4. **Install Drupal**
   ```bash
   drush site:install
   ```

5. **Import configuration**
   ```bash
   drush config:import
   ```

## Troubleshooting

### Common Issues

**DDEV won't start**
```bash
ddev restart
ddev logs
```

**Composer issues**
```bash
ddev composer clear-cache
ddev composer install
```

**Database connection errors**
```bash
ddev describe
# Check database credentials in settings.php
```

**Multisite routing issues**
```bash
# Check nginx configuration
ddev logs nginx

# Verify sites.php configuration
cat web/sites/sites.php
```

### Performance Optimization

```bash
# Enable caching
ddev drush en page_cache dynamic_page_cache

# Optimize autoloader
ddev composer dump-autoload --optimize

# Clear all caches
ddev drush cache:rebuild
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make changes in the project directory
4. Test with DDEV locally
5. Submit a pull request

### Code Standards

- Follow Drupal coding standards
- Use `ddev phpcs` for code style checking
- Write tests for custom modules
- Document API changes

## Security

- Keep Drupal core and modules updated
- Use strong API keys in production
- Configure proper file permissions
- Enable HTTPS for all sites
- Regular security updates via Composer

## Support

- **Documentation**: Check the main project README
- **Issues**: Report bugs in the main repository
- **DDEV Help**: https://ddev.readthedocs.io/
- **Drupal Documentation**: https://www.drupal.org/docs

## License

This project is licensed under the GPL-2.0-or-later license, consistent with Drupal core.