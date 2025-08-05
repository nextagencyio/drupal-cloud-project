# Drupal Cloud Template

A modern Drupal 11 template optimized for headless CMS development with GraphQL, OAuth 2.0, and Next.js integration.

## Features

- **Drupal 11** - Latest version with modern architecture
- **GraphQL API** - Powerful query language for efficient data fetching
- **OAuth 2.0 Authentication** - Secure API access with client credentials flow
- **Next.js Integration** - Built-in configuration for React/Next.js frontends
- **Admin Experience** - Gin admin theme with enhanced toolbar
- **Content Management** - Paragraphs module for flexible content building
- **SEO Ready** - Pathauto for clean URLs

## Quick Start

### Prerequisites

- PHP 8.1+
- Composer 2.0+
- MySQL/MariaDB or PostgreSQL
- DDEV (recommended for local development)

### Installation

1. **Create a new project**
   ```bash
   composer create-project nextagencio/drupal-cloud-project my-project
   cd my-project
   ```

2. **Install with DDEV (recommended)**
   ```bash
   ddev config --project-type=drupal --docroot=web
   ddev install "My Site Title"
   ```

   **Or install manually:**
   ```bash
   ddev start
   ddev composer install
   ddev drush site:install minimal --site-name="My Site" --account-name=admin --account-pass=admin
   ddev drush recipe recipes/dcloud-core -y
   ddev drush scr scripts/consumers-next.php
   ```

### Configuration

After installation, visit `/nextjs-config` to:
- View your GraphQL endpoint
- Get OAuth credentials for frontend integration
- Generate client secrets
- Copy environment variables for Next.js

## Architecture

### Included Modules

| Module | Purpose |
|--------|---------|
| **GraphQL** | Core GraphQL server implementation |
| **GraphQL Compose** | Auto-generated GraphQL schema from Drupal entities |
| **Simple OAuth** | OAuth 2.0 server for API authentication |
| **Paragraphs** | Flexible content components |
| **Pathauto** | Automated URL alias generation |
| **Admin Toolbar** | Enhanced admin experience |
| **Gin** | Modern admin theme |

### Custom Features

- **Next.js Config Module** - Configuration UI at `/nextjs-config`
- **OAuth Consumer Management** - Automated client setup
- **Environment Generation** - Copy-ready config for frontends

## Frontend Integration

### Next.js Setup

1. **Install dependencies**
   ```bash
   npm install @apollo/client graphql
   ```

2. **Configure Apollo Client**
   ```javascript
   // lib/apollo-client.js
   import { ApolloClient, InMemoryCache, createHttpLink } from '@apollo/client';
   import { setContext } from '@apollo/client/link/context';

   const httpLink = createHttpLink({
     uri: process.env.DRUPAL_GRAPHQL_URL,
   });

   const authLink = setContext(async (_, { headers }) => {
     const token = await getAccessToken();
     return {
       headers: {
         ...headers,
         authorization: token ? `Bearer ${token}` : "",
       }
     };
   });

   export const client = new ApolloClient({
     link: authLink.concat(httpLink),
     cache: new InMemoryCache(),
   });
   ```

3. **Environment Variables**
   ```env
   DRUPAL_BASE_URL=https://your-site.dcloud.ddev.site
   DRUPAL_GRAPHQL_URL=https://your-site.dcloud.ddev.site/graphql
   DRUPAL_CLIENT_ID=your_client_id
   DRUPAL_CLIENT_SECRET=your_client_secret
   DRUPAL_REVALIDATE_SECRET=your_revalidate_secret
   ```

### Sample GraphQL Queries

**Fetch Articles**
```graphql
query GetArticles {
  nodeArticles(first: 10) {
    nodes {
      id
      title
      body {
        processed
      }
      path
      created {
        timestamp
      }
    }
  }
}
```

**Fetch Pages**
```graphql
query GetPages {
  nodePages(first: 10) {
    nodes {
      id
      title
      body {
        processed
      }
      path
    }
  }
}
```

## Development Workflow

### Local Development

```bash
# Start DDEV
ddev start

# Install dependencies
ddev composer install

# Run database updates
ddev drush updb

# Clear caches
ddev drush cr

# Access the site
ddev launch
```

### Adding Content Types

1. Create content type in Drupal admin
2. Configure fields and display modes
3. Clear caches to update GraphQL schema
4. Query new content via GraphQL

### OAuth Management

- Visit `/admin/config/services/consumer` to manage OAuth clients
- Use `/nextjs-config` for frontend-friendly configuration
- Regenerate client secrets as needed for security

## Security

### Best Practices

- **Rotate OAuth secrets** regularly using the configuration UI
- **Use HTTPS** in production environments
- **Limit OAuth scope** to necessary permissions only
- **Monitor API usage** through Drupal logs

### Environment Security

- Store secrets in environment variables, not code
- Use different OAuth clients for dev/staging/production
- Implement rate limiting for API endpoints

## Deployment

### Production Checklist

- [ ] Configure trusted host patterns in `settings.php`
- [ ] Set up HTTPS and proper SSL certificates
- [ ] Configure caching (Redis/Memcache recommended)
- [ ] Set up automated backups
- [ ] Configure error logging and monitoring
- [ ] Generate production OAuth credentials
- [ ] Test GraphQL endpoints and authentication

### Environment Variables

```bash
# Database
DATABASE_URL=mysql://user:pass@host:port/database

# OAuth (generate via /nextjs-config)
OAUTH_CLIENT_ID=your_production_client_id
OAUTH_CLIENT_SECRET=your_production_client_secret

# Security
HASH_SALT=your_unique_hash_salt
```

## Troubleshooting

### Common Issues

**GraphQL Schema Not Updating**
```bash
ddev drush cr
ddev drush cache:rebuild
```

**OAuth Authentication Failing**
- Verify client credentials in `/admin/config/services/consumer`
- Check OAuth consumer is enabled and has correct permissions
- Ensure client secret is plain text (not hashed)

**Next.js Connection Issues**
- Verify CORS settings if needed
- Check network connectivity to Drupal backend
- Validate environment variables in frontend

### Logs

```bash
# Drupal logs
ddev drush watchdog:show --type=nextjs_config

# DDEV logs
ddev logs

# Web server logs
ddev logs -s web
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## License

GPL-2.0-or-later - see [LICENSE](LICENSE) file for details.

## Support

- **Documentation**: [GitHub Wiki](https://github.com/nextagencio/drupal-cloud-project/wiki)
- **Issues**: [GitHub Issues](https://github.com/nextagencio/drupal-cloud-project/issues)
- **Community**: [Drupal Slack #graphql](https://drupal.slack.com/channels/graphql)

---

**Next Agency** - Empowering headless CMS development
