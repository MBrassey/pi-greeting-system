#!/bin/bash

# Update Script for Raspberry Pi Facial Recognition System
# Handles system updates and maintenance

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() { echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }

# Check if services are running
check_services() {
    if systemctl is-active --quiet facial-recognition facial-recognition-web; then
        return 0
    else
        return 1
    fi
}

# Stop services
stop_services() {
    log "Stopping services..."
    sudo systemctl stop facial-recognition facial-recognition-web
}

# Start services
start_services() {
    log "Starting services..."
    sudo systemctl start facial-recognition facial-recognition-web
}

# Backup current installation
backup_current() {
    log "Creating backup..."
    timestamp=$(date +%Y%m%d_%H%M%S)
    tar -czf "backup_${timestamp}.tar.gz" \
        --exclude='*.pyc' \
        --exclude='__pycache__' \
        --exclude='venv' \
        --exclude='.git' \
        .
    info "Backup created: backup_${timestamp}.tar.gz"
}

# Update system packages
update_system() {
    log "Updating system packages..."
    sudo apt update
    sudo apt upgrade -y
}

# Update Python packages
update_python_packages() {
    log "Updating Python packages..."
    source venv/bin/activate
    pip install --upgrade pip
    pip install -r requirements.txt --upgrade
    deactivate
}

# Update application
update_application() {
    log "Checking for application updates..."
    
    # Store current branch
    current_branch=$(git rev-parse --abbrev-ref HEAD)
    
    # Fetch updates
    if ! git fetch origin $current_branch; then
        error "Failed to fetch updates"
        return 1
    fi
    
    # Check if updates are available
    if git diff --quiet HEAD origin/$current_branch; then
        info "No updates available"
        return 0
    fi
    
    # Create backup before updating
    backup_current
    
    # Pull updates
    if ! git pull origin $current_branch; then
        error "Failed to pull updates"
        return 1
    fi
    
    # Make scripts executable
    chmod +x *.sh
    
    return 0
}

# Clean up old files
cleanup() {
    log "Cleaning up..."
    
    # Remove old log files (keep last 7 days)
    find /var/log/facial-recognition -type f -name "*.log.*" -mtime +7 -delete
    
    # Remove old backups (keep last 5)
    ls -t backup_*.tar.gz 2>/dev/null | tail -n +6 | xargs -r rm
    
    # Clean Python cache
    find . -type f -name "*.pyc" -delete
    find . -type d -name "__pycache__" -exec rm -r {} +
}

# Main update sequence
main() {
    # Check if services are running
    services_were_running=false
    if check_services; then
        services_were_running=true
        stop_services
    fi
    
    # Run updates
    update_system
    
    if ! update_application; then
        error "Failed to update application"
        if [ "$services_were_running" = true ]; then
            start_services
        fi
        exit 1
    fi
    
    update_python_packages
    cleanup
    
    # Restart services if they were running
    if [ "$services_were_running" = true ]; then
        start_services
    fi
    
    log "Update completed successfully!"
    
    # Check if reboot is needed
    if [ -f /var/run/reboot-required ]; then
        warning "System reboot required to complete updates"
        echo "Please run: sudo reboot"
    fi
}

# Parse command line arguments
case "$1" in
    --check)
        # Just check for updates
        git fetch origin
        if git diff --quiet HEAD origin/$(git rev-parse --abbrev-ref HEAD); then
            info "System is up to date"
            exit 0
        else
            info "Updates are available"
            git log HEAD..origin/$(git rev-parse --abbrev-ref HEAD) --oneline
            exit 0
        fi
        ;;
    --backup)
        # Just create backup
        backup_current
        exit 0
        ;;
    --clean)
        # Just clean up
        cleanup
        exit 0
        ;;
    *)
        # Full update
        main
        ;;
esac 