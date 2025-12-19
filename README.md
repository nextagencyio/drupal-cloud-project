# Decoupled - Drupal 11 Codebase

Pure Drupal 11 multisite backend for decoupled.io. This repository contains only the Drupal codebase - custom modules, install profile, and configuration. For deployment infrastructure (Docker, Ansible, scripts, etc.), see the deployment documentation.

## Overview

This is a headless Drupal 11 installation providing GraphQL and JSON:API endpoints for decoupled applications. It supports multisite architecture where each "space" gets its own Drupal site with separate database.

**Key Capabilities:**
- **Multisite Architecture**: Each space gets its own Drupal site
- **GraphQL API**: Headless CMS with GraphQL Compose
- **OAuth Authentication**: Simple OAuth for secure API access
- **Custom Modules**: Purpose-built modules for decoupled.io functionality
- **Install Profile**: dc_core profile with modular installation system

## Project Structure

```
├── composer.json            # Drupal and module dependencies
├── composer.lock            # Locked dependency versions
├── config/                  # Configuration management
├── patches.lock.json        # Composer patches
├── private/                 # Private files directory
├── vendor/                  # Composer dependencies (gitignored)
└── web/                     # Drupal docroot
    ├── modules/custom/      # Custom modules
    │   ├── dcloud_chatbot/  # AI-powered content generation
    │   ├── dcloud_config/   # Space configuration
    │   ├── dcloud_import/   # Content import/export
    │   ├── dcloud_revalidate/ # Next.js revalidation
    │   ├── dcloud_usage/    # Usage statistics
    │   └── dcloud_user_redirect/ # Authentication
    ├── profiles/custom/     # Install profiles
    │   └── dc_core/         # Core install profile with recipes
    ├── sites/               # Multisite configurations
    └── themes/custom/       # Custom themes
```

## Requirements

- **PHP**: 8.3+
- **Database**: MySQL/MariaDB 11.4+ or PostgreSQL
- **Composer**: 2.x
- **Drush**: 13.x (included via Composer)

## Installation

This is a pure Drupal codebase. Install dependencies with Composer:

```bash
composer install
```

For deployment instructions (Docker, traditional hosting, etc.), see your deployment repository (e.g., `dcloud-docker`).

## Key Dependencies

### Core Drupal
- **drupal/core-recommended**: Drupal 11.2+
- **drupal/admin_toolbar**: Enhanced admin interface
- **drupal/gin**: Modern admin theme

### Headless/API
- **drupal/graphql**: GraphQL API foundation
- **drupal/graphql_compose**: Automatic schema generation
- **drupal/simple_oauth**: OAuth 2.0 authentication
- **drupal/decoupled_preview_iframe**: Preview support

### Content Management
- **drupal/paragraphs**: Flexible content components
- **drupal/field_group**: Organize form fields
- **drupal/pathauto**: Automatic URL aliases

### Development Tools
- **drush/drush**: Command-line interface (v13.x)
- **cweagans/composer-patches**: Apply patches via Composer

## Custom Modules

### dcloud_chatbot
AI-powered content generation and assistance.

**Features:**
- Content generation
- SEO optimization
- Content suggestions

**Endpoints:** `/api/chatbot/*`

### dcloud_config
Space configuration and setup wizards.

**Features:**
- Site configuration management
- Setup wizard flows
- Space-specific settings

### dcloud_import
Content import/export functionality.

**Features:**
- Bulk content import
- Export to JSON
- Migration support

**Endpoints:** `/api/dcloud-import`

### dcloud_revalidate
Next.js revalidation integration.

**Features:**
- On-demand revalidation
- Cache invalidation
- Webhook support

### dcloud_usage
Usage statistics and API request tracking.

**Features:**
- API request counts
- Content statistics
- GraphQL query metrics

**Endpoints:** `/api/dcloud/usage`

### dcloud_user_redirect
User authentication and redirection.

**Features:**
- Single sign-on flows
- Post-login redirects
- Role-based routing

## Install Profile

The project uses the **dc_core** install profile which contains Drupal recipes for modular installation. The install profile is located at `web/profiles/custom/dc_core/` and includes:

### Included Recipes

1. **dcloud-admin** - Admin interface with Gin theme and admin toolbar
2. **dcloud-api** - GraphQL, GraphQL Compose, Simple OAuth, and CORS configuration
3. **dcloud-fields** - Custom field configurations and paragraph types
4. **dcloud-core** - Core functionality with custom modules and site settings
5. **dcloud-content** - Sample content types (Article, Page) and taxonomies

### Installation

The dc_core profile is applied during site installation:

```bash
# Install new site with dc_core profile
drush site:install dc_core --site-name="My Site"

# Or use the install script
./scripts/install.sh "My Site"
```

The install profile automatically applies all recipes in the correct order during installation.

## GraphQL API

### Endpoints
- **GraphQL API**: `/graphql`
- **GraphQL Explorer**: `/graphql/explorer` (interactive IDE)
- **Schema**: Auto-generated from content types via GraphQL Compose

### Authentication
GraphQL requests require OAuth 2.0 Bearer tokens:

```bash
# Get OAuth token
curl -X POST https://yoursite.com/oauth/token \
  -d "grant_type=client_credentials" \
  -d "client_id=YOUR_CLIENT_ID" \
  -d "client_secret=YOUR_CLIENT_SECRET"

# Use token in GraphQL request
curl -X POST https://yoursite.com/graphql \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"query": "{ nodeArticles { nodes { title } } }"}'
```

### Example Query

```graphql
query {
  nodeArticles(first: 10) {
    nodes {
      title
      body {
        processed
      }
      author {
        displayName
      }
    }
  }
}
```

## JSON:API

Standard Drupal JSON:API is available at `/jsonapi` for all content entities.

## Multisite Architecture

This Drupal installation supports multisite via `web/sites/sites.php`. Each space gets:
- Separate site directory in `web/sites/<machine_name>/`
- Dedicated database
- Own `settings.php` configuration
- Individual OAuth consumers
- Isolated file storage

## Development Workflow

### Managing Dependencies

```bash
# Add new module
composer require drupal/module_name

# Update all packages
composer update

# Remove module
composer remove drupal/module_name

# Clear composer cache
composer clear-cache
```

### Using Drush

```bash
# Clear cache
drush cache:rebuild

# Export configuration
drush config:export

# Import configuration
drush config:import

# Check site status
drush status

# Run database updates
drush updatedb
```

## Configuration Management

Configuration is stored in the `config/` directory for version control. To sync configuration:

```bash
# Export current config
drush config:export

# Import config from files
drush config:import
```

For multisite, each site has its own config directory in `web/sites/<site>/files/config/sync`.

## Security Best Practices

- Keep Drupal core and modules updated via Composer
- Use strong OAuth client secrets in production
- Configure proper file permissions (typically www-data:www-data)
- Enable HTTPS for all production sites
- Regular security updates: `composer update drupal/core --with-dependencies`
- Review and apply Drupal security advisories

## Testing

```bash
# Run PHPUnit tests (if configured)
vendor/bin/phpunit web/modules/custom

# Check coding standards
vendor/bin/phpcs --standard=Drupal web/modules/custom
```

## Integration with decoupled.io Dashboard

The decoupled.io dashboard (Next.js app) integrates with this backend via:

1. **GraphQL API** for content operations
2. **OAuth 2.0** for authentication
3. **Custom REST endpoints** for space management
4. **Usage API** for statistics tracking
5. **Chatbot API** for AI features

OAuth credentials should be configured in the dashboard's `.env` file.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make changes to custom modules or install profile
4. Follow Drupal coding standards
5. Test thoroughly
6. Submit a pull request

### Code Standards

- Follow [Drupal coding standards](https://www.drupal.org/docs/develop/standards)
- Use meaningful commit messages
- Document custom code
- Update this README for significant changes

## Support

- **Drupal Documentation**: https://www.drupal.org/docs
- **GraphQL Compose**: https://www.drupal.org/project/graphql_compose
- **Simple OAuth**: https://www.drupal.org/project/simple_oauth
- **Drupal Install Profiles**: https://www.drupal.org/docs/distributions-and-profiles

## License

This project is licensed under GPL-2.0-or-later, consistent with Drupal core.
