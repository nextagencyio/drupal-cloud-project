#!/bin/bash

# Decoupled Drupal Docker Deployment Script
# This script handles git pull and setup on the server

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log() {
    echo -e "${BLUE}[DEPLOY]${NC} $1"
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

# Configuration
# Detect environment and set paths accordingly
if [[ -d "/opt/drupalcloud" ]]; then
    # Production environment
    PROJECT_DIR="/opt/drupalcloud"
    SSH_KEY_PATH="/root/.ssh/drupalcloud-docker-deploy"
elif git rev-parse --git-dir > /dev/null 2>&1; then
    # Local environment - use current directory if it's a git repo
    PROJECT_DIR="$(pwd)"
    # Look for SSH key in common locations
    if [[ -f "$HOME/.ssh/drupalcloud-docker-deploy" ]]; then
        SSH_KEY_PATH="$HOME/.ssh/drupalcloud-docker-deploy"
    elif [[ -f "$HOME/.ssh/id_rsa" ]]; then
        SSH_KEY_PATH="$HOME/.ssh/id_rsa"
    else
        SSH_KEY_PATH="/root/.ssh/drupalcloud-docker-deploy"
    fi
else
    log_error "Not in a valid project directory and /opt/drupalcloud doesn't exist"
    exit 1
fi

REPO_URL="git@github.com:nextagencyio/drupal-cloud-docker.git"

# Main deployment function
deploy() {
    log "Starting Decoupled Drupal Docker deployment..."
    log "Project directory: $PROJECT_DIR"
    log "SSH key path: $SSH_KEY_PATH"

    # Change to project directory
    if [[ ! -d "$PROJECT_DIR" ]]; then
        log_error "Project directory not found: $PROJECT_DIR"
        log "Current directory: $(pwd)"
        log "Available directories:"
        ls -la / | grep opt || echo "No /opt directory found"
        exit 1
    fi

    cd "$PROJECT_DIR"

    # Check if this is a git repository
    if [[ ! -d ".git" ]]; then
        log_error "Not a git repository: $PROJECT_DIR"
        exit 1
    fi

    # Show current status
    log "Current directory: $(pwd)"
    log "Current branch: $(git branch --show-current)"
    log "Current commit: $(git rev-parse --short HEAD)"

    # Setup SSH for git operations
    log "Setting up SSH authentication..."

    # Check if SSH key exists
    if [[ ! -f "$SSH_KEY_PATH" ]]; then
        log_error "SSH key not found at: $SSH_KEY_PATH"
        exit 1
    fi

    # Fix key permissions
    chmod 600 "$SSH_KEY_PATH"

    # Start SSH agent and add key
    eval "$(ssh-agent -s)"
    ssh-add "$SSH_KEY_PATH"

    # Test SSH connection to GitHub
    log "Testing SSH connection to GitHub..."
    if ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
        log_success "SSH authentication successful"
    else
        log_warning "SSH test completed (this is normal - GitHub doesn't allow shell access)"
    fi

    # Configure git remote to use SSH
    log "Configuring git remote for SSH..."
    git remote set-url origin "$REPO_URL"

    # Fetch latest changes using SSH
    log "Fetching latest changes..."
    git fetch origin

    # Show what will be updated
    commits_behind=$(git rev-list --count HEAD..origin/main)
    if [[ "$commits_behind" -gt 0 ]]; then
        log "Found $commits_behind new commits to pull"
        git log --oneline HEAD..origin/main | head -5
    else
        log "Already up to date"
    fi

    # Pull latest changes
    log "Pulling latest changes..."
    git pull origin main

    # Show new status
    log_success "Git pull completed"
    log "New commit: $(git rev-parse --short HEAD)"

    # Run setup script with preserved SSL config
    if [[ -f "./setup.sh" ]]; then
        log "Running setup script..."
        chmod +x ./setup.sh
        SKIP_COMPOSE_MODIFICATION=true ./setup.sh
        log_success "Setup script completed"
    else
        log_warning "No setup.sh found, skipping setup"
    fi

    log_success "Deployment completed successfully!"
}

# Show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Deploys the latest code from GitHub and runs setup."
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  --dry-run      Show what would be updated without deploying"
    echo ""
    echo "Examples:"
    echo "  $0             # Deploy latest changes"
    echo "  $0 --dry-run   # Check what would be updated"
    echo ""
}

# Parse command line arguments
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Dry run mode
if [[ "$DRY_RUN" == true ]]; then
    log "Dry run mode - checking for updates..."

    cd "$PROJECT_DIR"
    git fetch origin

    commits_behind=$(git rev-list --count HEAD..origin/main)
    if [[ "$commits_behind" -gt 0 ]]; then
        log "Would pull $commits_behind new commits:"
        git log --oneline HEAD..origin/main
    else
        log "Already up to date - no deployment needed"
    fi

    exit 0
fi

# Run deployment
deploy