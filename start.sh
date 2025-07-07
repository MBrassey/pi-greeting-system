#!/bin/bash

# Raspberry Pi Facial Recognition System Startup Script
# This script handles system initialization and startup

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

# Check if running on Raspberry Pi
if ! grep -q "Raspberry Pi" /proc/cpuinfo; then
    warning "This system may not be a Raspberry Pi. Some features might not work as expected."
fi

# Check if virtual environment exists
if [ ! -d "venv" ]; then
    error "Virtual environment not found. Please run install.sh first."
    exit 1
fi

# Check for required files
required_files=("face_recognition.py" "config.yml" "manage_faces.py" "web_interface.py")
for file in "${required_files[@]}"; do
    if [ ! -f "$file" ]; then
        error "Required file $file not found."
        exit 1
    fi
done

# Check for required directories
required_dirs=("data/known_faces" "data/unknown_faces" "data/logs" "templates" "static")
for dir in "${required_dirs[@]}"; do
    if [ ! -d "$dir" ]; then
        log "Creating directory: $dir"
        mkdir -p "$dir"
    fi
done

# Check camera
if ! ls /dev/video* &> /dev/null; then
    warning "No video devices found. Please check camera connection."
    warning "If using Pi Camera, make sure it's enabled in raspi-config"
fi

# Check audio
if ! command -v espeak &> /dev/null; then
    warning "espeak not found. Voice greetings may not work."
else
    info "Testing audio system..."
    if ! espeak "System starting" 2>/dev/null; then
        warning "Audio test failed. Please check speaker connection and volume."
    fi
fi

# Check disk space
disk_space=$(df -h . | awk 'NR==2 {print $4}')
disk_usage=$(df -h . | awk 'NR==2 {print $5}' | sed 's/%//')
if [ "$disk_usage" -gt 90 ]; then
    warning "Low disk space: $disk_space available (${disk_usage}% used)"
fi

# Check memory
total_mem=$(free -m | awk 'NR==2 {print $2}')
if [ "$total_mem" -lt 1024 ]; then
    warning "System has less than 1GB RAM ($total_mem MB). Performance may be affected."
fi

# Check Python version
python_version=$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')
if (( $(echo "$python_version < 3.7" | bc -l) )); then
    error "Python 3.7 or newer is required. Found version $python_version"
    exit 1
fi

# Activate virtual environment
log "Activating virtual environment..."
source venv/bin/activate

# Check Python dependencies
log "Checking Python dependencies..."
if ! pip freeze | grep -q "face-recognition"; then
    error "Required Python packages not installed. Please run install.sh first."
    exit 1
fi

# Create/check log directory
log_dir="/var/log/facial-recognition"
if [ ! -d "$log_dir" ]; then
    if ! sudo mkdir -p "$log_dir"; then
        error "Failed to create log directory: $log_dir"
        exit 1
    fi
    sudo chown -R $USER:$USER "$log_dir"
fi

# Check configuration
log "Validating configuration..."
if ! python3 -c "import yaml; yaml.safe_load(open('config.yml'))"; then
    error "Invalid configuration file. Please check config.yml"
    exit 1
fi

# Start web interface in background
log "Starting web interface..."
python3 web_interface.py > "$log_dir/web.log" 2>&1 &
web_pid=$!

# Wait for web interface to start
sleep 2
if ! kill -0 $web_pid 2>/dev/null; then
    error "Web interface failed to start. Check $log_dir/web.log for details."
    exit 1
fi

# Start face recognition system
log "Starting facial recognition system..."
python3 face_recognition.py > "$log_dir/system.log" 2>&1 &
system_pid=$!

# Wait for system to start
sleep 2
if ! kill -0 $system_pid 2>/dev/null; then
    error "Facial recognition system failed to start. Check $log_dir/system.log for details."
    kill $web_pid
    exit 1
fi

# Save PIDs for shutdown
echo "$web_pid" > .web.pid
echo "$system_pid" > .system.pid

# Print status
log "System started successfully!"
echo ""
echo -e "${GREEN}=== SYSTEM STATUS ===${NC}"
echo -e "Web Interface PID: ${BLUE}$web_pid${NC}"
echo -e "Recognition System PID: ${BLUE}$system_pid${NC}"
echo -e "Log Directory: ${BLUE}$log_dir${NC}"
echo ""
echo -e "${GREEN}=== ACCESS INFORMATION ===${NC}"
echo -e "Web Interface: ${BLUE}http://localhost:8080${NC}"
echo -e "Default Username: ${BLUE}admin${NC}"
echo ""
echo -e "${YELLOW}Press Ctrl+C to stop the system${NC}"

# Trap Ctrl+C
trap cleanup INT

cleanup() {
    log "Shutting down..."
    kill $web_pid 2>/dev/null
    kill $system_pid 2>/dev/null
    rm -f .web.pid .system.pid
    log "System stopped"
    exit 0
}

# Monitor processes
while kill -0 $web_pid 2>/dev/null && kill -0 $system_pid 2>/dev/null; do
    sleep 1
done

# If we get here, something died
if ! kill -0 $web_pid 2>/dev/null; then
    error "Web interface crashed. Check $log_dir/web.log for details."
fi
if ! kill -0 $system_pid 2>/dev/null; then
    error "Recognition system crashed. Check $log_dir/system.log for details."
fi

# Cleanup
cleanup 