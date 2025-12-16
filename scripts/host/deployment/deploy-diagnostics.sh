#!/bin/bash
set -e

# Deploy Diagnostics Script
# Connects to production server and runs comprehensive nginx/docker diagnostics

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SERVER_IP="64.23.230.99"
SERVER_USER="root"
PROJECT_DIR="/opt/drupalcloud"

# Function to print colored output
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
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

# Main diagnostics function
run_diagnostics() {
    log_info "Connecting to production server for diagnostics with SSH key forwarding..."
    
    ssh -A "$SERVER_USER@$SERVER_IP" << 'EOF'
        set -e
        
        # Colors for remote output
        RED='\033[0;31m'
        GREEN='\033[0;32m'
        YELLOW='\033[1;33m'
        BLUE='\033[0;34m'
        NC='\033[0m'
        
        log_info() { echo -e "${BLUE}[REMOTE]${NC} $1"; }
        log_success() { echo -e "${GREEN}[REMOTE]${NC} $1"; }
        log_warning() { echo -e "${YELLOW}[REMOTE]${NC} $1"; }
        log_error() { echo -e "${RED}[REMOTE]${NC} $1"; }
        
        cd /opt/drupalcloud
        
        log_info "=== UPDATING CODE ==="
        git pull origin main || log_warning "Git pull failed - continuing with diagnostics"
        
        log_info "=== DOCKER CONTAINER STATUS ==="
        docker compose -f docker-compose.prod.yml ps
        
        log_info "=== NGINX PROXY LOGS ==="
        docker compose -f docker-compose.prod.yml logs --tail=20 nginx
        
        log_info "=== DRUPAL CONTAINER LOGS ==="
        docker compose -f docker-compose.prod.yml logs --tail=20 drupal
        
        log_info "=== NGINX PROXY CONFIGURATION ==="
        docker compose -f docker-compose.prod.yml exec nginx ls -la /etc/nginx/vhost.d/
        docker compose -f docker-compose.prod.yml exec nginx cat /etc/nginx/conf.d/default.conf 2>/dev/null || log_warning "Could not read default.conf"
        
        log_info "=== CHECKING VIRTUAL_HOST ENVIRONMENT ==="
        docker compose -f docker-compose.prod.yml exec drupal printenv | grep VIRTUAL
        
        log_info "=== DRUPAL WEB ROOT STATUS ==="
        docker compose -f docker-compose.prod.yml exec drupal ls -la /var/www/html/
        docker compose -f docker-compose.prod.yml exec drupal test -f /var/www/html/web/index.php && log_success "Drupal index.php exists" || log_error "Drupal index.php missing"
        
        log_info "=== NETWORK CONNECTIVITY ==="
        docker compose -f docker-compose.prod.yml exec nginx curl -I http://drupal-web/ 2>/dev/null || log_warning "Cannot connect to drupal-web from nginx"
        
        log_info "=== PORT BINDINGS ==="
        docker compose -f docker-compose.prod.yml port nginx 80 2>/dev/null || log_warning "Port 80 not bound"
        docker compose -f docker-compose.prod.yml port nginx 443 2>/dev/null || log_warning "Port 443 not bound"
        
        log_info "=== FIREWALL STATUS ==="
        ufw status || log_warning "UFW not available"
        
        log_info "=== EXTERNAL CONNECTIVITY TEST ==="
        curl -I http://localhost/ 2>/dev/null || log_warning "Cannot connect to localhost:80"
        
        log_info "=== LETSENCRYPT LOGS ==="
        docker compose -f docker-compose.prod.yml logs --tail=10 letsencrypt
        
        log_info "=== DOCKER NETWORKS ==="
        docker network ls | grep drupal
        docker compose -f docker-compose.prod.yml exec drupal hostname -I
        
        log_success "Diagnostics completed!"
EOF
}

# Run diagnostics
main() {
    log_info "Starting deploy diagnostics..."
    run_diagnostics
    log_success "Deploy diagnostics completed!"
}

# Execute main function
main "$@"