#!/bin/bash

# System Compatibility Check Script for Raspberry Pi Facial Recognition System
# Verifies system requirements and dependencies before installation

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

# Function to check if a command exists
check_command() {
    if command -v "$1" &> /dev/null; then
        return 0
    else
        return 1
    fi
}

# Function to check Python version
check_python_version() {
    if ! check_command python3; then
        error "Python 3 is not installed"
        return 1
    fi
    
    version=$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')
    if (( $(echo "$version < 3.7" | bc -l) )); then
        error "Python 3.7 or newer is required (found $version)"
        return 1
    fi
    info "Python version: $version"
    return 0
}

# Function to check system memory
check_memory() {
    total_mem=$(free -m | awk 'NR==2 {print $2}')
    if [ "$total_mem" -lt 1024 ]; then
        error "Insufficient memory: ${total_mem}MB (minimum 1GB required)"
        return 1
    fi
    info "Memory: ${total_mem}MB"
    return 0
}

# Function to check disk space
check_disk_space() {
    free_space=$(df -m / | awk 'NR==2 {print $4}')
    if [ "$free_space" -lt 5120 ]; then
        error "Insufficient disk space: ${free_space}MB (minimum 5GB required)"
        return 1
    fi
    info "Free disk space: ${free_space}MB"
    return 0
}

# Function to check Raspberry Pi model
check_pi_model() {
    if [ -f /proc/device-tree/model ]; then
        model=$(cat /proc/device-tree/model)
        if [[ $model == *"Raspberry Pi"* ]]; then
            if [[ $model == *"3"* ]] || [[ $model == *"4"* ]]; then
                info "Raspberry Pi model: $model"
                return 0
            else
                error "Unsupported Raspberry Pi model: $model (3 or 4 required)"
                return 1
            fi
        else
            error "Not running on a Raspberry Pi"
            return 1
        fi
    else
        error "Cannot determine system model"
        return 1
    fi
}

# Function to check camera
check_camera() {
    # Check for USB camera
    if [ -e "/dev/video0" ]; then
        info "USB camera detected at /dev/video0"
        return 0
    fi
    
    # Check for Pi Camera
    if check_command vcgencmd; then
        if vcgencmd get_camera | grep -q "supported=1 detected=1"; then
            info "Raspberry Pi Camera detected"
            return 0
        fi
    fi
    
    error "No camera detected"
    return 1
}

# Function to check audio
check_audio() {
    if ! check_command aplay; then
        error "Audio utilities not installed"
        return 1
    fi
    
    if aplay -l | grep -q "no soundcards found"; then
        error "No audio device found"
        return 1
    fi
    
    info "Audio device detected"
    return 0
}

# Function to check required packages
check_required_packages() {
    local missing_packages=()
    local packages=(
        "python3-dev"
        "python3-pip"
        "python3-venv"
        "build-essential"
        "cmake"
        "pkg-config"
        "libgtk-3-dev"
        "espeak"
    )
    
    for pkg in "${packages[@]}"; do
        if ! dpkg -l | grep -q "^ii  $pkg "; then
            missing_packages+=("$pkg")
        fi
    done
    
    if [ ${#missing_packages[@]} -eq 0 ]; then
        info "All required packages are installed"
        return 0
    else
        error "Missing required packages: ${missing_packages[*]}"
        echo "Install with: sudo apt install ${missing_packages[*]}"
        return 1
    fi
}

# Function to check GPU memory
check_gpu_memory() {
    if check_command vcgencmd; then
        gpu_mem=$(vcgencmd get_mem gpu | cut -d= -f2 | tr -d 'M')
        if [ "$gpu_mem" -lt 128 ]; then
            warning "GPU memory might be too low: ${gpu_mem}MB (recommend 128MB minimum)"
            echo "Add 'gpu_mem=128' to /boot/config.txt to increase"
            return 1
        fi
        info "GPU memory: ${gpu_mem}MB"
        return 0
    fi
    warning "Cannot check GPU memory"
    return 1
}

# Function to check network
check_network() {
    if ! ping -c 1 8.8.8.8 &> /dev/null; then
        error "No internet connection"
        return 1
    fi
    info "Network connection: OK"
    return 0
}

# Function to check user permissions
check_permissions() {
    local user=$USER
    local required_groups=("video" "audio" "gpio" "i2c")
    local missing_groups=()
    
    for group in "${required_groups[@]}"; do
        if ! groups "$user" | grep -q "\b$group\b"; then
            missing_groups+=("$group")
        fi
    done
    
    if [ ${#missing_groups[@]} -eq 0 ]; then
        info "User has all required group permissions"
        return 0
    else
        warning "User '$user' is missing groups: ${missing_groups[*]}"
        echo "Add with: sudo usermod -a -G ${missing_groups[*]} $user"
        return 1
    fi
}

# Main check sequence
log "Starting system compatibility check..."
echo ""

# Initialize counters
errors=0
warnings=0

# Run checks
echo -e "${BLUE}=== Hardware Checks ===${NC}"
check_pi_model || ((errors++))
check_memory || ((errors++))
check_disk_space || ((errors++))
check_camera || ((errors++))
check_audio || ((warnings++))
check_gpu_memory || ((warnings++))

echo -e "\n${BLUE}=== Software Checks ===${NC}"
check_python_version || ((errors++))
check_required_packages || ((errors++))
check_network || ((errors++))
check_permissions || ((warnings++))

# Print summary
echo ""
echo -e "${GREEN}=== Check Summary ===${NC}"
echo "Errors: $errors"
echo "Warnings: $warnings"

# Print result
echo ""
if [ $errors -eq 0 ]; then
    if [ $warnings -eq 0 ]; then
        echo -e "${GREEN}All checks passed! System is ready for installation.${NC}"
        exit 0
    else
        echo -e "${YELLOW}System meets minimum requirements but has some warnings.${NC}"
        echo "You can proceed with installation, but some features might not work optimally."
        exit 0
    fi
else
    echo -e "${RED}System does not meet minimum requirements.${NC}"
    echo "Please fix the errors above before proceeding with installation."
    exit 1
fi 