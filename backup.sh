#!/bin/bash

# Backup Script for Raspberry Pi Facial Recognition System
# Handles data backup and restoration

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

# Create backup
create_backup() {
    local backup_dir="data"
    local config_dir="config"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="backup_${timestamp}.tar.gz"
    
    log "Creating backup: $backup_file"
    
    # Create backup
    tar -czf "$backup_file" \
        --exclude='*.pyc' \
        --exclude='__pycache__' \
        --exclude='venv' \
        --exclude='.git' \
        "$backup_dir" "$config_dir" config.yml
    
    if [ $? -eq 0 ]; then
        info "Backup created successfully: $backup_file"
        
        # Calculate size
        size=$(du -h "$backup_file" | cut -f1)
        info "Backup size: $size"
        
        # List contents
        info "Backup contents:"
        tar -tvf "$backup_file" | awk '{print $6}' | sed 's/^/  /'
        
        return 0
    else
        error "Failed to create backup"
        return 1
    fi
}

# Restore backup
restore_backup() {
    local backup_file="$1"
    
    if [ ! -f "$backup_file" ]; then
        error "Backup file not found: $backup_file"
        return 1
    fi
    
    log "Restoring from backup: $backup_file"
    
    # Create temporary directory
    local temp_dir=$(mktemp -d)
    
    # Extract backup to temp directory
    tar -xzf "$backup_file" -C "$temp_dir"
    
    if [ $? -ne 0 ]; then
        error "Failed to extract backup"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Verify backup contents
    if [ ! -d "$temp_dir/data" ] || [ ! -d "$temp_dir/config" ]; then
        error "Invalid backup file: missing required directories"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Stop services if running
    services_were_running=false
    if check_services; then
        services_were_running=true
        stop_services
    fi
    
    # Backup current data
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local current_backup="current_${timestamp}.tar.gz"
    log "Creating backup of current data: $current_backup"
    tar -czf "$current_backup" data config config.yml
    
    # Restore data
    log "Restoring data..."
    rm -rf data config
    mv "$temp_dir/data" "$temp_dir/config" .
    
    # Restore configuration
    if [ -f "$temp_dir/config.yml" ]; then
        cp "$temp_dir/config.yml" .
    fi
    
    # Clean up
    rm -rf "$temp_dir"
    
    # Start services if they were running
    if [ "$services_were_running" = true ]; then
        start_services
    fi
    
    log "Restore completed successfully!"
    info "Previous data backed up to: $current_backup"
    return 0
}

# List backups
list_backups() {
    log "Available backups:"
    if ls backup_*.tar.gz >/dev/null 2>&1; then
        for backup in backup_*.tar.gz; do
            size=$(du -h "$backup" | cut -f1)
            date=$(date -r "$backup" "+%Y-%m-%d %H:%M:%S")
            echo -e "${BLUE}$backup${NC}"
            echo "  Size: $size"
            echo "  Date: $date"
            echo "  Contents:"
            tar -tvf "$backup" | awk '{print "    " $6}' | head -n 5
            if [ $(tar -tvf "$backup" | wc -l) -gt 5 ]; then
                echo "    ..."
            fi
            echo
        done
    else
        info "No backups found"
    fi
}

# Clean old backups
clean_backups() {
    local keep=$1
    
    if ! [[ "$keep" =~ ^[0-9]+$ ]]; then
        keep=5
    fi
    
    log "Cleaning old backups (keeping last $keep)..."
    local count=$(ls -1 backup_*.tar.gz 2>/dev/null | wc -l)
    
    if [ "$count" -gt "$keep" ]; then
        ls -t backup_*.tar.gz | tail -n +$((keep + 1)) | xargs rm
        info "Removed $((count - keep)) old backup(s)"
    else
        info "No old backups to remove"
    fi
}

# Show usage
usage() {
    echo "Usage: $0 [command] [options]"
    echo
    echo "Commands:"
    echo "  backup              Create new backup"
    echo "  restore <file>      Restore from backup file"
    echo "  list               List available backups"
    echo "  clean [n]          Remove old backups (keep last n, default 5)"
    echo
    echo "Examples:"
    echo "  $0 backup          Create new backup"
    echo "  $0 restore backup_20240101_120000.tar.gz"
    echo "  $0 list           List all backups"
    echo "  $0 clean 3        Keep only last 3 backups"
}

# Main logic
case "$1" in
    backup)
        create_backup
        ;;
    restore)
        if [ -z "$2" ]; then
            error "Please specify backup file to restore"
            usage
            exit 1
        fi
        restore_backup "$2"
        ;;
    list)
        list_backups
        ;;
    clean)
        clean_backups "$2"
        ;;
    *)
        usage
        exit 1
        ;;
esac 