# Decoupled - Drupal 11 Composer Template

A Drupal 11 Composer template optimized for headless/decoupled architectures. This template provides a complete Drupal codebase with GraphQL, JSON:API, and custom modules designed for modern JavaScript frontends (React, Next.js, Vue, etc.).

## Overview

This Composer template creates a production-ready headless Drupal 11 installation. Unlike traditional Drupal sites, this is specifically configured for decoupled applications where Drupal serves as a content API backend.

**What This Template Provides:**
- **Headless-First**: GraphQL and JSON:API endpoints out of the box
- **OAuth 2.0 Authentication**: Secure API access for frontend applications
- **Modern Admin Experience**: Gin theme and enhanced admin tools
- **Content Flexibility**: Paragraphs, flexible fields, and structured content
- **Developer-Friendly**: Drush CLI, configuration management, and modular architecture
- **Production-Ready**: Optimized for performance and security

**Host Anywhere**: This template works on any hosting environment that supports Drupal - traditional servers, Docker, Platform.sh, Pantheon, Acquia, DigitalOcean, AWS, or your own infrastructure.

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

- **PHP**: 8.3+ with extensions: mysql, xml, mbstring, curl, zip, gd, intl, bcmath, opcache, soap
- **Database**: MySQL 8.0+, MariaDB 11.4+, or PostgreSQL 13+
- **Composer**: 2.x
- **Web Server**: Apache 2.4+ or Nginx 1.18+
- **Drush**: 13.x (included via Composer)

## Installation

### Quick Start

```bash
# Create a new project from this template
composer create-project nextagencyio/drupal-cloud-project mysite

# Navigate to project directory
cd mysite

# Install Drupal with the dc_core profile
vendor/bin/drush site:install dc_core \
  --site-name="My Decoupled Site" \
  --account-name=admin \
  --account-pass=admin \
  --db-url=mysql://user:pass@localhost/dbname

# Access your site
open http://localhost/mysite
```

### What Gets Installed

The `dc_core` install profile automatically configures:
1. **Admin Interface**: Gin theme + Admin Toolbar
2. **API Layer**: GraphQL + GraphQL Compose + JSON:API
3. **Authentication**: Simple OAuth with consumer setup
4. **Content Structure**: Paragraphs + field configurations
5. **Custom Modules**: All dcloud_* modules enabled
6. **Sample Content**: Article and Page content types

### Hosting Options

This template works with any hosting environment:

**Traditional Hosting**
- cPanel/Plesk shared hosting
- VPS with Apache/Nginx
- Traditional LAMP/LEMP stacks

**Modern PaaS**
- Platform.sh
- Pantheon
- Acquia Cloud
- Laravel Forge

**Cloud Providers**
- AWS (EC2, Elastic Beanstalk, Lightsail)
- DigitalOcean Droplets
- Google Cloud Platform
- Microsoft Azure

**Containerized**
- Docker + Docker Compose
- Kubernetes
- Amazon ECS/Fargate

**No vendor lock-in!** Use what works best for your team.

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

### Example JSON:API Request

```bash
# Get all articles
curl https://yoursite.com/jsonapi/node/article \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN"

# Get single article
curl https://yoursite.com/jsonapi/node/article/UUID \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN"
```

## Multisite Support (Optional)

This template supports Drupal's multisite architecture. To enable:

1. Edit `web/sites/sites.php`
2. Create site directories in `web/sites/<domain>/`
3. Each site gets:
   - Separate database
   - Own `settings.php`
   - Individual OAuth consumers
   - Isolated file storage

**Note**: Multisite is optional. Most decoupled applications use single-site installations.

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

## Connecting Your Frontend

This Drupal backend is designed to work with any JavaScript frontend:

### Next.js Example

```typescript
// lib/drupal.ts
import { DrupalClient } from "next-drupal";

export const drupal = new DrupalClient(
  process.env.NEXT_PUBLIC_DRUPAL_BASE_URL,
  {
    auth: {
      clientId: process.env.DRUPAL_CLIENT_ID,
      clientSecret: process.env.DRUPAL_CLIENT_SECRET,
    },
  }
);

// pages/index.tsx
export async function getStaticProps() {
  const articles = await drupal.getResourceCollection("node--article");
  return { props: { articles } };
}
```

### React/Vue Example

```javascript
// api/drupal.js
const DRUPAL_URL = 'https://yoursite.com';

async function getOAuthToken() {
  const response = await fetch(`${DRUPAL_URL}/oauth/token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'client_credentials',
      client_id: process.env.DRUPAL_CLIENT_ID,
      client_secret: process.env.DRUPAL_CLIENT_SECRET,
    }),
  });
  const data = await response.json();
  return data.access_token;
}

async function queryGraphQL(query) {
  const token = await getOAuthToken();
  const response = await fetch(`${DRUPAL_URL}/graphql`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${token}`,
    },
    body: JSON.stringify({ query }),
  });
  return response.json();
}
```

### Environment Variables

```env
# .env.local
NEXT_PUBLIC_DRUPAL_BASE_URL=https://yoursite.com
DRUPAL_CLIENT_ID=your-oauth-client-id
DRUPAL_CLIENT_SECRET=your-oauth-client-secret
```

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

## Why Use This Template?

### vs. Standard Drupal
- ✅ Pre-configured for headless/decoupled architecture
- ✅ GraphQL and OAuth ready out of the box
- ✅ Modern admin theme (Gin) instead of Seven
- ✅ Optimized for API performance
- ✅ No frontend theme bloat

### vs. Contenta CMS
- ✅ Based on latest Drupal 11 (not Drupal 8)
- ✅ Uses Drupal Recipes for modular installation
- ✅ GraphQL Compose (auto-generated schema)
- ✅ Active maintenance and updates
- ✅ Production-proven at decoupled.io

### vs. Building From Scratch
- ✅ Saves weeks of configuration
- ✅ Best practices baked in
- ✅ Battle-tested custom modules
- ✅ Regular security updates
- ✅ Community-driven improvements

## Use Cases

- **Marketing Sites**: Drupal for content management, Next.js/Gatsby for frontend
- **Mobile Apps**: Use GraphQL API for iOS/Android apps
- **Headless Commerce**: Drupal content + Shopify/Stripe
- **Multi-Channel Publishing**: Single content source, multiple frontends
- **JAMstack Sites**: Static site generation with Drupal as CMS
- **Progressive Web Apps**: Modern JavaScript frameworks + Drupal API

## Support & Resources

- **Drupal Documentation**: https://www.drupal.org/docs
- **GraphQL Compose**: https://www.drupal.org/project/graphql_compose
- **Simple OAuth**: https://www.drupal.org/project/simple_oauth
- **Next-Drupal**: https://next-drupal.org (Next.js integration)
- **Decoupled Drupal**: https://www.drupal.org/docs/8/modules/decoupled-drupal

## License

This project is licensed under GPL-2.0-or-later, consistent with Drupal core.
