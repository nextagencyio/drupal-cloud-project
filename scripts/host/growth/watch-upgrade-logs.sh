#!/bin/bash

# Watch Upgrade Logs Script
# Monitors the most recent upgrade attempt in real-time

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Find most recent upgrade directory
UPGRADE_DIR=$(ls -dt /tmp/dcloud-upgrade-* 2>/dev/null | head -1)

if [[ -z "$UPGRADE_DIR" ]]; then
    echo -e "${RED}No upgrade directories found in /tmp/${NC}"
    exit 1
fi

echo -e "${BLUE}===========================================================${NC}"
echo -e "${BLUE}Monitoring Upgrade Logs${NC}"
echo -e "${BLUE}===========================================================${NC}"
echo -e "${CYAN}Directory:${NC} $UPGRADE_DIR"
echo -e "${BLUE}===========================================================${NC}"
echo ""

# Function to display a log file
show_log() {
    local log_file="$1"
    local log_name="$2"

    if [[ -f "$log_file" ]]; then
        echo -e "${GREEN}=== $log_name ===${NC}"
        cat "$log_file"
        echo ""
    fi
}

# Function to tail a log file if it's growing
tail_log() {
    local log_file="$1"
    local log_name="$2"

    if [[ -f "$log_file" ]]; then
        echo -e "${YELLOW}Watching $log_name (Ctrl+C to stop)...${NC}"
        tail -f "$log_file"
    fi
}

# List all files in the directory
echo -e "${CYAN}Files in upgrade directory:${NC}"
ls -lh "$UPGRADE_DIR"
echo ""

# Show all logs
show_log "$UPGRADE_DIR/upsun-create-output.log" "Upsun Project Creation"
show_log "$UPGRADE_DIR/git-push.log" "Git Push to Upsun"
show_log "$UPGRADE_DIR/db-upload.log" "Database Upload"
show_log "$UPGRADE_DIR/db-import.log" "Database Import"
show_log "$UPGRADE_DIR/files-upload.log" "Files Upload"
show_log "$UPGRADE_DIR/cache-clear.log" "Cache Clear"
show_log "$UPGRADE_DIR/drush-status.log" "Drupal Status Check"

# If git-push.log exists and is the newest, tail it
if [[ -f "$UPGRADE_DIR/git-push.log" ]]; then
    NEWEST=$(ls -t "$UPGRADE_DIR"/*.log 2>/dev/null | head -1)
    if [[ "$NEWEST" == "$UPGRADE_DIR/git-push.log" ]]; then
        tail_log "$UPGRADE_DIR/git-push.log" "Git Push (Live)"
    fi
fi

echo -e "${GREEN}===========================================================${NC}"
echo -e "${GREEN}Log review complete${NC}"
echo -e "${GREEN}===========================================================${NC}"
