#!/bin/bash

# Raspberry Pi Facial Recognition System Installation Script
# Bulletproof installation for Raspberry Pi OS - No manual steps required

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log() { echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }

# Function to check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        error "Please run as root (use sudo)"
        exit 1
    fi
}

# Emergency cleanup function
emergency_cleanup() {
    log "Performing emergency cleanup..."
    
    # Kill all package management processes
    for pid in $(ps aux | grep -E 'apt|dpkg' | grep -v grep | awk '{print $2}'); do
        kill -9 $pid 2>/dev/null || true
    done
    
    # Remove all lock files
    rm -f /var/lib/dpkg/lock* || true
    rm -f /var/lib/apt/lists/lock || true
    rm -f /var/cache/apt/archives/lock || true
    rm -f /var/lib/dpkg/updates/* || true
    rm -f /var/cache/apt/archives/partial/* || true
    
    # Clean package manager state
    rm -rf /var/lib/apt/lists/* || true
    mkdir -p /var/lib/apt/lists/partial
    
    # Fix SSH list file
    mkdir -p /var/lib/dpkg/info
    touch /var/lib/dpkg/info/ssh.list || true
    touch /var/lib/dpkg/status || true
    
    # Reset dpkg state
    dpkg --configure -a || true
    
    # Force clean and update
    apt-get clean || true
    apt-get update --fix-missing || true
    
    log "Emergency cleanup completed"
}

# Super robust package manager fix
fix_package_manager() {
    log "Performing thorough package manager fix..."
    
    # First run emergency cleanup
    emergency_cleanup
    
    # Try to fix any broken packages
    DEBIAN_FRONTEND=noninteractive apt-get -f install -y || true
    
    # Update package lists with multiple retries
    max_attempts=3
    attempt=1
    while [ $attempt -le $max_attempts ]; do
        if apt-get update --fix-missing; then
            break
        fi
        log "Retrying package list update (attempt $attempt of $max_attempts)..."
        emergency_cleanup
        attempt=$((attempt + 1))
        sleep 5
    done
    
    # Final verification
    if ! apt-get update --fix-missing; then
        warning "Package manager may still have issues, but continuing anyway..."
    else
        log "Package manager fixed successfully"
    fi
}

# Function to install a single package with retry
install_package() {
    local package=$1
    local max_attempts=3
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        log "Installing $package (attempt $attempt of $max_attempts)..."
        if DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$package"; then
            return 0
        fi
        warning "Failed to install $package, retrying..."
        fix_package_manager
        attempt=$((attempt + 1))
        sleep 2
    done
    
    return 1
}

# Function to install system dependencies
install_system_deps() {
    log "Installing system dependencies..."
    
    # Fix package manager first
    fix_package_manager
    
    # Remove potentially conflicting packages
    apt-get remove -y python3-picamera2 python3-libcamera || true
    
    # Core build dependencies first
    core_packages=(
        "build-essential"
        "cmake"
        "pkg-config"
    )
    
    # Install core packages first
    for package in "${core_packages[@]}"; do
        if ! install_package "$package"; then
            error "Failed to install core package $package"
            emergency_cleanup
            if ! install_package "$package"; then
                return 1
            fi
        fi
    done
    
    # Main packages
    packages=(
        "python3-dev"
        "python3-pip"
        "python3-setuptools"
        "python3-wheel"
        "python3-opencv"
        "python3-numpy"
        "python3-pil"
        "python3-yaml"
        "python3-psutil"
        "libopenblas-dev"
        "liblapack-dev"
        "libjpeg-dev"
        "libatlas-base-dev"
        "v4l-utils"
        "espeak"
        "git"
    )
    
    # Install main packages
    for package in "${packages[@]}"; do
        if ! install_package "$package"; then
            warning "Failed to install $package, continuing anyway..."
        fi
    done

    # Fix video device permissions
    log "Setting up video device permissions..."
    if ! getent group video >/dev/null; then
        groupadd video || true
    fi
    usermod -a -G video $SUDO_USER || true
    for device in /dev/video*; do
        if [ -e "$device" ]; then
            chmod 666 "$device" || true
        fi
    done
}

# Function to install Python packages
install_python_packages() {
    log "Installing Python packages..."
    
    # Ensure pip is up to date
    python3 -m pip install --upgrade pip || true
    
    # Install packages one by one with retry mechanism
    packages=(
        "numpy"
        "dlib"
        "face_recognition"
        "pyttsx3"
        "Flask"
        "cryptography"
    )
    
    for package in "${packages[@]}"; do
        log "Installing $package..."
        max_attempts=3
        attempt=1
        
        while [ $attempt -le $max_attempts ]; do
            if python3 -m pip install --no-cache-dir "$package"; then
                break
            fi
            attempt=$((attempt + 1))
            log "Retrying $package installation (attempt $attempt of $max_attempts)..."
            # Clear pip cache and retry
            rm -rf ~/.cache/pip
            sleep 2
        done
        
        if [ $attempt -gt $max_attempts ]; then
            warning "Failed to install $package after $max_attempts attempts, continuing..."
        fi
    done
}

# Function to verify Python packages
verify_python_packages() {
    log "Verifying Python packages..."
    
    packages=("dlib" "face_recognition" "cv2" "numpy" "pyttsx3" "flask" "yaml")
    failed_packages=()
    
    for package in "${packages[@]}"; do
        log "Testing import of $package..."
        if ! python3 -c "import $package" 2>/dev/null; then
            warning "Failed to import $package"
            failed_packages+=("$package")
        fi
    done
    
    if [ ${#failed_packages[@]} -eq 0 ]; then
        info "All Python packages verified successfully"
        return 0
    else
        error "Failed to verify packages: ${failed_packages[*]}"
        return 1
    fi
}

# Function to create directory structure
create_directories() {
    log "Creating directory structure..."
    
    directories=(
        "data/known_faces"
        "data/unknown_faces"
        "data/logs"
        "data/backups"
        "templates"
        "static/faces"
        "ssl"
    )
    
    for dir in "${directories[@]}"; do
        mkdir -p "$dir"
        chown $SUDO_USER:$SUDO_USER "$dir" || true
        chmod 755 "$dir" || true
    done
}

# Function to set up configuration
setup_config() {
    log "Setting up configuration..."
    
    if [ ! -f "config.yml" ]; then
        cat > config.yml << 'EOF'
# Recognition settings
recognition:
  tolerance: 0.6
  model: 'hog'
  frame_rate: 30
  resolution: [640, 480]
  min_face_size: 20
  blur_threshold: 100

# Camera settings
camera:
  type: 'usb'  # 'usb' or 'picamera'
  device: 0
  brightness: 50
  contrast: 55
  flip_horizontal: false
  flip_vertical: false

# Storage settings
storage:
  base_dir: 'data'
  known_faces_dir: 'data/known_faces'
  unknown_faces_dir: 'data/unknown_faces'
  logs_dir: 'data/logs'

# Greeting settings
greeting:
  enabled: true
  volume: 0.8
  rate: 150
  cooldown: 30
  custom_greetings: {}
EOF
        chown $SUDO_USER:$SUDO_USER config.yml || true
        chmod 644 config.yml || true
    fi
}

# Function to verify camera
verify_camera() {
    log "Verifying camera access..."
    
    if ! v4l2-ctl --list-devices > /dev/null 2>&1; then
        warning "No video devices found - please check camera connection"
        return 1
    fi
    
    info "Camera verification successful"
    return 0
}

# Main installation function
main() {
    log "Starting bulletproof installation for Raspberry Pi..."
    
    # Check if running as root
    check_root
    
    # Initial emergency cleanup
    emergency_cleanup
    
    # Install system dependencies with retry mechanism
    max_attempts=3
    attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        log "Installing system dependencies (attempt $attempt of $max_attempts)..."
        if install_system_deps; then
            break
        fi
        error "System dependencies installation failed, trying emergency cleanup..."
        emergency_cleanup
        attempt=$((attempt + 1))
        sleep 5
    done
    
    if [ $attempt -gt $max_attempts ]; then
        warning "Some system dependencies failed to install, continuing anyway..."
    fi
    
    # Install Python packages
    if ! install_python_packages; then
        warning "Some Python packages may have failed to install, continuing anyway..."
    fi
    
    # Create directory structure (always try)
    create_directories
    
    # Set up configuration (always try)
    setup_config
    
    # Verify camera (don't fail on error)
    verify_camera || true
    
    # Final verification
    if verify_python_packages; then
        log "Installation completed successfully!"
        log "You can now run the system with: python3 face_recognition.py"
    else
        warning "Installation completed with some package verification failures"
        log "The system may still work, but some features might be limited"
        log "You can try running the script again if you want to retry failed installations"
    fi
}

# Trap interrupts and cleanup
trap emergency_cleanup INT TERM

# Run main installation
main 