# Decoupled Drupal Project

This is the **production Drupal codebase** for the Decoupled.io platform, featuring the `dc_core` installation profile.

## 🚨 CRITICAL: This Repo Powers Production

**This repository (`nextagencyio/decoupled-project`) is deployed to ALL production droplets.**

- Each production droplet has `/opt/drupalcloud` as a git clone of this repo
- Code changes pushed here are deployed via Ansible to all production droplets
- Docker images are pre-built and pulled from Docker Hub (NOT built locally)

## Deployment Process

### 1. Make Changes Locally
Edit files in `templates/decoupled-project/` within the `decoupled-dashboard` monorepo:
```bash
cd /Users/jcallicott/nodejs/decoupled-dashboard/templates/decoupled-project
# Make your changes to Drupal code, modules, themes, etc.
```

### 2. Commit and Push
```bash
git add .
git commit -m "Your commit message"
git push
```

### 3. Deploy to Production
From the **decoupled-dashboard** repo root:
```bash
cd /Users/jcallicott/nodejs/decoupled-dashboard
gh workflow run deploy-code-changes.yml --repo nextagencyio/decoupled-dashboard
```

### 4. What Happens During Deployment
- Ansible connects to all production droplets
- Runs `git reset --hard origin/main` to pull latest code
- Checks commit message for `[reinstall-template]` keyword
- If keyword present: Reinstalls template site, regenerates backup
- If keyword absent: Skips template reinstall (faster)
- Runs database updates (`drush updb`) on all sites
- Clears caches (`drush cr`) on all sites

## Template Reinstall Keyword

Use `[reinstall-template]` in your commit message to trigger a full template reinstall:

```bash
git commit -m "[reinstall-template] Add new custom module to dc_core profile"
```

**When to use:**
- Adding/removing modules from `dc_core.info.yml`
- Changing installation profile configuration
- Updating dc_core install hooks
- Adding new custom modules that need to be enabled by default

**When NOT to use:**
- Regular code updates to existing modules
- Theme changes
- Configuration updates
- Bug fixes

Without the keyword, deployment only updates code and runs updb/cr (much faster).

## Important Notes

- **DO NOT** use `build:` in `docker-compose.prod.yml` - causes OOM on 1GB droplets
- Always use `image: jrcallicott/drupalcloud-drupal:latest` for production
- Docker images must be pre-built and pushed to Docker Hub before deployment
- Local development uses `templates/decoupled-docker` (separate from this repo)

## Repository Structure

```
web/
├── profiles/
│   └── dc_core/          # Installation profile
│       ├── modules/      # Custom modules
│       ├── themes/       # Custom themes
│       └── dc_core.info.yml
├── sites/
│   └── default/
│       └── settings.php
└── ...

docker-compose.prod.yml    # Production Docker config (uses pre-built images)
```

## Last Updated

2025-12-24
