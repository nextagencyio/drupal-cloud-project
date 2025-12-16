#!/bin/bash
set -e

# Automated Ubuntu Updates and Maintenance Setup
# Sets up nightly updates with automatic restarts when needed

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Install unattended-upgrades for automatic security updates
setup_unattended_upgrades() {
    log_info "Setting up unattended upgrades..."
    
    # Install unattended-upgrades
    apt update
    apt install -y unattended-upgrades apt-listchanges
    
    # Configure unattended-upgrades
    cat > /etc/apt/apt.conf.d/50unattended-upgrades <<'EOF'
// Automatically upgrade packages from these (origin:archive) pairs
//
// Note that in Ubuntu, updates may come from security updates
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
    "${distro_id}:${distro_codename}-updates";
};

// Python regular expressions, matching packages to exclude from upgrading
Unattended-Upgrade::Package-Blacklist {
    // The following matches all packages starting with linux-
//  "linux-";

    // Use $ to explicitely define the end of a package name. Without
    // the $, "libc6" would match all of them.
//  "libc6$";
//  "libc6-dev$";
//  "libc6-i686$";

    // Special characters need escaping
//  "libstdc\+\+6$";

    // The following matches packages like xen-system-amd64, xen-utils-4.1,
    // xenstore-utils and libxenstore3.0
//  "(lib)?xen(store)?";

    // For more information about Python regular expressions, see
    // https://docs.python.org/3/library/re.html
};

// This option allows you to control if on a unclean dpkg exit
// unattended-upgrades will automatically run 
//   dpkg --force-confold --configure -a
// The default is true, to ensure updates keep getting installed
Unattended-Upgrade::AutoFixInterruptedDpkg "true";

// Split the upgrade into the smallest possible chunks so that
// they can be interrupted with SIGTERM. This makes the upgrade
// a bit slower but it has the benefit that shutdown while a upgrade
// is running is possible (with a small delay)
Unattended-Upgrade::MinimalSteps "true";

// Install all updates when the machine is shutting down
// instead of doing it in the background while the machine is running.
// This will (obviously) make shutdown slower.
Unattended-Upgrade::InstallOnShutdown "false";

// Send email to this address for problems or packages upgrades
// If empty or unset then no email is sent, make sure that you
// have a working mail setup on your system. A package that provides
// 'mailx' must be installed. E.g. "user@example.com"
//Unattended-Upgrade::Mail "";

// Set this value to "true" to get emails only on errors. Default
// is to always send a mail if Unattended-Upgrade::Mail is set
//Unattended-Upgrade::MailOnlyOnError "true";

// Remove unused automatically installed kernel-related packages
// (kernel images, kernel headers and kernel version locked tools).
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";

// Do automatic removal of newly unused dependencies after the upgrade
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";

// Do automatic removal of unused packages after the upgrade
// (equivalent to apt autoremove)
Unattended-Upgrade::Remove-Unused-Dependencies "true";

// Automatically reboot *WITHOUT CONFIRMATION* if
//  the file /var/run/reboot-required is found after the upgrade
Unattended-Upgrade::Automatic-Reboot "true";

// Automatically reboot even if there are users currently logged in
// when Unattended-Upgrade::Automatic-Reboot is set to true
Unattended-Upgrade::Automatic-Reboot-WithUsers "true";

// If automatic reboot is enabled and needed, reboot at the specific
// time instead of immediately
//  Default: "now"
Unattended-Upgrade::Automatic-Reboot-Time "02:00";

// Use apt bandwidth limit feature, this example limits the download
// speed to 70kb/sec
//Acquire::http::Dl-Limit "70";

// Enable logging to syslog. Default is False
Unattended-Upgrade::SyslogEnable "true";

// Specify syslog facility. Default is daemon
Unattended-Upgrade::SyslogFacility "daemon";

// Download and install upgrades only on AC power
// (i.e. skip or gracefully stop updates on battery)
// Unattended-Upgrade::OnlyOnACPower "true";

// Download and install upgrades only on non-metered connection
// (i.e. skip or gracefully stop updates on a metered connection)
// Unattended-Upgrade::Skip-Updates-On-Metered-Connections "true";

// Verbose logging
// Unattended-Upgrade::Verbose "false";

// Print debugging information both in unattended-upgrades and
// in unattended-upgrade-shutdown
// Unattended-Upgrade::Debug "false";
EOF

    # Configure auto-upgrades
    cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Download-Upgradeable-Packages "1";
EOF

    # Enable and start unattended-upgrades
    systemctl enable unattended-upgrades
    systemctl start unattended-upgrades
    
    log_success "Unattended upgrades configured successfully"
}

# Create pre/post reboot scripts for Docker containers
create_docker_maintenance_scripts() {
    log_info "Creating Docker maintenance scripts..."
    
    # Create scripts directory
    mkdir -p /opt/maintenance
    
    # Pre-reboot script - gracefully stop containers
    cat > /opt/maintenance/pre-reboot.sh <<'EOF'
#!/bin/bash
# Pre-reboot script - gracefully stop Docker containers

PROJECT_DIR="/opt/drupalcloud"
LOG_FILE="/var/log/docker-maintenance.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [PRE-REBOOT] $1" >> $LOG_FILE
}

if [[ -d "$PROJECT_DIR" ]]; then
    log "Stopping Docker containers gracefully..."
    cd "$PROJECT_DIR"
    
    # Stop containers gracefully
    if docker compose -f docker-compose.prod.yml ps | grep -q "Up"; then
        docker compose -f docker-compose.prod.yml stop
        log "Docker containers stopped successfully"
    else
        log "No running containers found"
    fi
else
    log "Project directory not found: $PROJECT_DIR"
fi
EOF

    # Post-reboot script - restart containers
    cat > /opt/maintenance/post-reboot.sh <<'EOF'
#!/bin/bash
# Post-reboot script - restart Docker containers

PROJECT_DIR="/opt/drupalcloud"
LOG_FILE="/var/log/docker-maintenance.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [POST-REBOOT] $1" >> $LOG_FILE
}

# Wait for system to be ready
sleep 30

log "Post-reboot maintenance starting..."

# Ensure Docker is running
if ! systemctl is-active --quiet docker; then
    log "Starting Docker service..."
    systemctl start docker
    sleep 10
fi

if [[ -d "$PROJECT_DIR" ]]; then
    cd "$PROJECT_DIR"
    
    # Check if containers exist and start them
    if [[ -f "docker-compose.prod.yml" ]]; then
        log "Starting Docker containers..."
        docker compose -f docker-compose.prod.yml up -d
        
        # Wait for containers to be ready
        sleep 30
        
        # Check container status
        if docker compose -f docker-compose.prod.yml ps | grep -q "Up"; then
            log "Docker containers started successfully"
            
            # Run health check
            /opt/drupalcloud/scripts/health-check.sh --quick >> $LOG_FILE 2>&1 || true
        else
            log "ERROR: Docker containers failed to start"
            # Send alert or notification here if needed
        fi
    else
        log "Docker compose file not found"
    fi
else
    log "Project directory not found: $PROJECT_DIR"
fi

log "Post-reboot maintenance completed"
EOF

    # Make scripts executable
    chmod +x /opt/maintenance/pre-reboot.sh
    chmod +x /opt/maintenance/post-reboot.sh
    
    log_success "Docker maintenance scripts created"
}

# Setup systemd services for pre/post reboot
setup_reboot_services() {
    log_info "Setting up reboot services..."
    
    # Pre-reboot service
    cat > /etc/systemd/system/docker-pre-reboot.service <<'EOF'
[Unit]
Description=Docker Pre-Reboot Maintenance
DefaultDependencies=false
Before=shutdown.target reboot.target halt.target
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=true
ExecStart=/opt/maintenance/pre-reboot.sh
TimeoutStartSec=30

[Install]
WantedBy=halt.target reboot.target shutdown.target
EOF

    # Post-reboot service
    cat > /etc/systemd/system/docker-post-reboot.service <<'EOF'
[Unit]
Description=Docker Post-Reboot Maintenance
After=docker.service
Wants=docker.service

[Service]
Type=oneshot
ExecStart=/opt/maintenance/post-reboot.sh
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF

    # Enable services
    systemctl daemon-reload
    systemctl enable docker-pre-reboot.service
    systemctl enable docker-post-reboot.service
    
    log_success "Reboot services configured"
}

# Create maintenance cron jobs
setup_cron_jobs() {
    log_info "Setting up maintenance cron jobs..."
    
    # Create maintenance script for regular cleanup
    cat > /opt/maintenance/nightly-maintenance.sh <<'EOF'
#!/bin/bash
# Nightly maintenance script

PROJECT_DIR="/opt/drupalcloud"
LOG_FILE="/var/log/nightly-maintenance.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> $LOG_FILE
}

log "=== Nightly maintenance started ==="

# Docker cleanup
log "Running Docker cleanup..."
docker system prune -f >> $LOG_FILE 2>&1

# Clean old logs
log "Cleaning old logs..."
find /var/log -name "*.log" -type f -mtime +30 -delete 2>/dev/null || true
journalctl --vacuum-time=30d >> $LOG_FILE 2>&1 || true

# Clean old backups (keep 30 days)
if [[ -d "/opt/backups" ]]; then
    log "Cleaning old backups..."
    find /opt/backups -name "*.tar.gz" -type f -mtime +30 -delete >> $LOG_FILE 2>&1 || true
fi

# Check disk space and alert if low
DISK_USAGE=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
if [[ $DISK_USAGE -gt 85 ]]; then
    log "WARNING: Disk usage is at ${DISK_USAGE}%"
    # Add alerting mechanism here (email, webhook, etc.)
fi

# Check if containers are healthy
if [[ -d "$PROJECT_DIR" ]]; then
    cd "$PROJECT_DIR"
    if ! docker compose -f docker-compose.prod.yml ps | grep -q "Up"; then
        log "WARNING: Some Docker containers are not running"
        # Try to restart
        log "Attempting to restart containers..."
        docker compose -f docker-compose.prod.yml up -d >> $LOG_FILE 2>&1
    fi
fi

log "=== Nightly maintenance completed ==="
EOF

    chmod +x /opt/maintenance/nightly-maintenance.sh
    
    # Add cron jobs
    cat > /tmp/docker-maintenance-cron <<'EOF'
# Docker maintenance cron jobs

# Nightly maintenance at 2:30 AM
30 2 * * * /opt/maintenance/nightly-maintenance.sh

# Weekly cleanup on Sunday at 3 AM
0 3 * * 0 /opt/maintenance/weekly-maintenance.sh
EOF

    # Create weekly maintenance script
    cat > /opt/maintenance/weekly-maintenance.sh <<'EOF'
#!/bin/bash
# Weekly maintenance script

LOG_FILE="/var/log/weekly-maintenance.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> $LOG_FILE
}

log "=== Weekly maintenance started ==="

# Update package lists
log "Updating package lists..."
apt update >> $LOG_FILE 2>&1

# Clean package cache
log "Cleaning package cache..."
apt autoclean >> $LOG_FILE 2>&1
apt autoremove -y >> $LOG_FILE 2>&1

# Docker cleanup (more aggressive)
log "Running aggressive Docker cleanup..."
docker system prune -af --volumes >> $LOG_FILE 2>&1 || true

# Check for available updates (but don't install - let unattended-upgrades handle it)
UPDATES=$(apt list --upgradable 2>/dev/null | wc -l)
log "Available updates: $UPDATES"

log "=== Weekly maintenance completed ==="
EOF

    chmod +x /opt/maintenance/weekly-maintenance.sh
    
    # Install cron jobs
    crontab -l > /tmp/current-cron 2>/dev/null || echo "" > /tmp/current-cron
    cat /tmp/current-cron /tmp/docker-maintenance-cron | crontab -
    rm /tmp/docker-maintenance-cron /tmp/current-cron
    
    log_success "Maintenance cron jobs configured"
}

# Create monitoring and alerting setup
setup_monitoring() {
    log_info "Setting up basic monitoring..."
    
    # Create monitoring script
    cat > /opt/maintenance/health-check.sh <<'EOF'
#!/bin/bash
# Health check script

PROJECT_DIR="/opt/drupalcloud"
LOG_FILE="/var/log/health-check.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> $LOG_FILE
}

check_containers() {
    if [[ -d "$PROJECT_DIR" ]]; then
        cd "$PROJECT_DIR"
        
        # Check if all expected containers are running
        local expected_containers=("drupal" "nginx" "letsencrypt")
        local failed=0
        
        for container in "${expected_containers[@]}"; do
            if ! docker compose -f docker-compose.prod.yml ps "$container" | grep -q "Up"; then
                log "ERROR: Container $container is not running"
                ((failed++))
            fi
        done
        
        if [[ $failed -eq 0 ]]; then
            log "All containers are healthy"
            return 0
        else
            log "$failed containers are unhealthy"
            return 1
        fi
    else
        log "Project directory not found"
        return 1
    fi
}

check_disk_space() {
    local usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
    if [[ $usage -gt 90 ]]; then
        log "CRITICAL: Disk usage is at ${usage}%"
        return 1
    elif [[ $usage -gt 85 ]]; then
        log "WARNING: Disk usage is at ${usage}%"
        return 1
    else
        log "Disk usage is OK (${usage}%)"
        return 0
    fi
}

check_memory() {
    local mem_usage=$(free | grep Mem | awk '{printf("%.0f", $3/$2 * 100.0)}')
    if [[ $mem_usage -gt 95 ]]; then
        log "CRITICAL: Memory usage is at ${mem_usage}%"
        return 1
    elif [[ $mem_usage -gt 85 ]]; then
        log "WARNING: Memory usage is at ${mem_usage}%"
        return 1
    else
        log "Memory usage is OK (${mem_usage}%)"
        return 0
    fi
}

# Run checks
log "=== Health check started ==="
check_containers
check_disk_space  
check_memory
log "=== Health check completed ==="
EOF

    chmod +x /opt/maintenance/health-check.sh
    
    # Add health check to cron (every 15 minutes) - using the enhanced health check script
    (crontab -l 2>/dev/null; echo "*/15 * * * * /opt/drupalcloud/scripts/health-check.sh --quick --fix") | crontab -
    
    log_success "Health monitoring configured"
}

# Main function
main() {
    log_info "🔧 Setting up automated Ubuntu updates and maintenance..."
    echo
    
    check_root
    
    setup_unattended_upgrades
    create_docker_maintenance_scripts
    setup_reboot_services
    setup_cron_jobs
    setup_monitoring
    
    # Create log directory and set permissions
    mkdir -p /var/log
    touch /var/log/docker-maintenance.log
    touch /var/log/nightly-maintenance.log
    touch /var/log/weekly-maintenance.log
    touch /var/log/health-check.log
    
    # Set up log rotation
    cat > /etc/logrotate.d/docker-maintenance <<'EOF'
/var/log/docker-maintenance.log
/var/log/nightly-maintenance.log
/var/log/weekly-maintenance.log
/var/log/health-check.log
{
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
}
EOF

    echo
    log_success "🎉 Automated maintenance setup completed!"
    echo
    log_info "📋 What's been configured:"
    echo "  ✅ Automatic security updates (unattended-upgrades)"
    echo "  ✅ Automatic reboots when needed (2:00 AM)"
    echo "  ✅ Pre/post reboot Docker container management"  
    echo "  ✅ Nightly maintenance (2:30 AM)"
    echo "  ✅ Weekly cleanup (Sunday 3:00 AM)"
    echo "  ✅ Health monitoring (every 15 minutes)"
    echo "  ✅ Log rotation (30 day retention)"
    echo
    log_info "📊 Monitor logs:"
    echo "  sudo tail -f /var/log/docker-maintenance.log"
    echo "  sudo tail -f /var/log/nightly-maintenance.log"
    echo "  sudo tail -f /var/log/health-check.log"
    echo
    log_info "🔧 Manual commands:"
    echo "  sudo /opt/maintenance/health-check.sh        # Run health check"
    echo "  sudo /opt/maintenance/nightly-maintenance.sh # Run maintenance"
    echo "  sudo unattended-upgrades --dry-run -d       # Test updates"
    echo
}

main "$@"