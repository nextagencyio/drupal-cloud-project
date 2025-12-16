#!/bin/bash
set -e

# Docker Restart Script
# Restarts all Docker containers with optional rebuild and cleanup

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
COMPOSE_FILE="docker-compose.prod.yml"

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

# Show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --rebuild         Rebuild Docker images before restart"
    echo "  --clean           Clean up unused Docker resources after restart"
    echo "  --pull            Pull latest images before restart"
    echo "  --logs            Show logs after restart"
    echo "  --no-cache        Use --no-cache when rebuilding"
    echo "  --remote          Run on remote server (requires SSH config)"
    echo "  -h, --help        Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                    # Simple restart"
    echo "  $0 --rebuild          # Rebuild and restart"
    echo "  $0 --rebuild --clean  # Rebuild, restart, and cleanup"
    echo "  $0 --remote           # Restart on production server"
}

# Parse command line arguments
REBUILD=false
CLEAN=false
PULL=false
SHOW_LOGS=false
NO_CACHE=false
REMOTE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --rebuild)
            REBUILD=true
            shift
            ;;
        --clean)
            CLEAN=true
            shift
            ;;
        --pull)
            PULL=true
            shift
            ;;
        --logs)
            SHOW_LOGS=true
            shift
            ;;
        --no-cache)
            NO_CACHE=true
            shift
            ;;
        --remote)
            REMOTE=true
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

# Remote execution
if [ "$REMOTE" = true ]; then
    log_info "Executing docker restart on remote server..."
    
    # Build command to run remotely
    REMOTE_CMD="cd /opt/drupalcloud && "
    
    if [ "$PULL" = true ]; then
        REMOTE_CMD+="git pull origin main && "
    fi
    
    REMOTE_CMD+="docker compose -f $COMPOSE_FILE down && "
    
    if [ "$REBUILD" = true ]; then
        if [ "$NO_CACHE" = true ]; then
            REMOTE_CMD+="docker compose -f $COMPOSE_FILE build --no-cache && "
        else
            REMOTE_CMD+="docker compose -f $COMPOSE_FILE build && "
        fi
    fi
    
    REMOTE_CMD+="docker compose -f $COMPOSE_FILE up -d"
    
    if [ "$CLEAN" = true ]; then
        REMOTE_CMD+=" && docker system prune -f"
    fi
    
    if [ "$SHOW_LOGS" = true ]; then
        REMOTE_CMD+=" && docker compose -f $COMPOSE_FILE logs --tail=20"
    fi
    
    ssh root@64.23.230.99 "$REMOTE_CMD"
    log_success "Remote docker restart completed!"
    exit 0
fi

# Local execution
log_info "Starting Docker container restart..."

# Check if compose file exists
if [[ ! -f "$COMPOSE_FILE" ]]; then
    log_error "Docker compose file not found: $COMPOSE_FILE"
    exit 1
fi

# Pull latest images if requested
if [ "$PULL" = true ]; then
    log_info "Pulling latest images..."
    docker compose -f "$COMPOSE_FILE" pull
fi

# Stop containers
log_info "Stopping containers..."
docker compose -f "$COMPOSE_FILE" down

# Rebuild if requested
if [ "$REBUILD" = true ]; then
    log_info "Rebuilding Docker images..."
    if [ "$NO_CACHE" = true ]; then
        docker compose -f "$COMPOSE_FILE" build --no-cache
    else
        docker compose -f "$COMPOSE_FILE" build
    fi
fi

# Start containers
log_info "Starting containers..."
docker compose -f "$COMPOSE_FILE" up -d

# Wait for containers to be ready
log_info "Waiting for containers to be ready..."
sleep 10

# Check container status
log_info "Container status:"
docker compose -f "$COMPOSE_FILE" ps

# Clean up if requested
if [ "$CLEAN" = true ]; then
    log_info "Cleaning up unused Docker resources..."
    docker system prune -f
fi

# Show logs if requested
if [ "$SHOW_LOGS" = true ]; then
    log_info "Recent container logs:"
    docker compose -f "$COMPOSE_FILE" logs --tail=20
fi

log_success "Docker restart completed!"

# Health check
log_info "Performing basic health check..."
if docker compose -f "$COMPOSE_FILE" ps | grep -q "Up"; then
    log_success "Containers are running"
else
    log_warning "Some containers may not be running properly"
fi