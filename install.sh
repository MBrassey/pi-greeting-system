#!/bin/bash

# Raspberry Pi Facial Recognition System Installation Script
# Optimized for Raspberry Pi 5 running Raspberry Pi OS

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

# Function to fix package manager
fix_package_manager() {
    log "Fixing package manager state..."
    
    # Fix any broken dependencies
    apt-get -f install -y
    
    # Clean package cache
    apt-get clean
    apt-get autoclean
    
    # Update package lists
    rm -f /var/lib/apt/lists/lock
    rm -f /var/cache/apt/archives/lock
    rm -f /var/lib/dpkg/lock*
    dpkg --configure -a
    apt-get update
}

# Function to install system dependencies
install_system_deps() {
    log "Installing system dependencies..."
    
    # Fix package manager first
    fix_package_manager
    
    # Install essential packages
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        python3-dev \
        python3-pip \
        python3-setuptools \
        python3-opencv \
        python3-numpy \
        python3-pil \
        python3-yaml \
        python3-psutil \
        python3-picamera2 \
        cmake \
        build-essential \
        libopenblas-dev \
        liblapack-dev \
        libjpeg-dev \
        libatlas-base-dev \
        v4l-utils \
        espeak \
        git \
        || {
            error "Failed to install system packages"
            exit 1
        }

    # Fix video device permissions
    log "Setting up video device permissions..."
    
    # Add video group if it doesn't exist
    if ! getent group video >/dev/null; then
        groupadd video
    fi
    
    # Add user to video group
    usermod -a -G video $SUDO_USER
    
    # Set permissions for video devices
    for device in /dev/video*; do
        if [ -e "$device" ]; then
            chmod 666 "$device"
        fi
    done
}

# Function to install Python packages
install_python_packages() {
    log "Installing Python packages..."
    
    # Install dlib using apt instead of building from source
    log "Installing dlib using apt..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y python3-dlib || {
        error "Failed to install python3-dlib"
        exit 1
    }
    
    # Install face_recognition using pip
    log "Installing face_recognition..."
    python3 -m pip install --no-cache-dir face_recognition || {
        error "Failed to install face_recognition"
        exit 1
    }
    
    # Install other required packages
    log "Installing additional Python packages..."
    python3 -m pip install --no-cache-dir \
        pyttsx3 \
        Flask \
        cryptography \
        || {
            error "Failed to install Python packages"
            exit 1
        }
}

# Function to verify Python packages
verify_python_packages() {
    log "Verifying Python packages..."
    
    # List of required packages
    packages=("dlib" "face_recognition" "cv2" "numpy" "pyttsx3" "flask" "yaml")
    
    for package in "${packages[@]}"; do
        log "Testing import of $package..."
        if ! python3 -c "import $package" 2>/dev/null; then
            error "Failed to import $package"
            return 1
        fi
    done
    
    info "All Python packages verified successfully"
    return 0
}

# Function to create directory structure
create_directories() {
    log "Creating directory structure..."
    
    # Create required directories
    mkdir -p \
        data/known_faces \
        data/unknown_faces \
        data/logs \
        data/backups \
        templates \
        static/faces \
        ssl
    
    # Set permissions
    chown -R $SUDO_USER:$SUDO_USER \
        data \
        templates \
        static \
        ssl
    
    chmod -R 755 \
        data \
        templates \
        static \
        ssl
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
        chown $SUDO_USER:$SUDO_USER config.yml
    fi
}

# Function to verify camera
verify_camera() {
    log "Verifying camera access..."
    
    if ! v4l2-ctl --list-devices > /dev/null 2>&1; then
        error "No video devices found"
        return 1
    fi
    
    info "Camera verification successful"
    return 0
}

# Main installation function
main() {
    log "Starting installation for Raspberry Pi 5..."
    
    # Check if running as root
    check_root
    
    # Install system dependencies
    install_system_deps || {
        error "Failed to install system dependencies"
        exit 1
    }
    
    # Install Python packages
    install_python_packages || {
        error "Failed to install Python packages"
        exit 1
    }
    
    # Verify Python packages
    verify_python_packages || {
        error "Python package verification failed"
        exit 1
    }
    
    # Create directory structure
    create_directories || {
        error "Failed to create directories"
        exit 1
    }
    
    # Set up configuration
    setup_config || {
        error "Failed to set up configuration"
        exit 1
    }
    
    # Verify camera
    verify_camera || {
        warning "Camera verification failed - please check your camera connection"
    }
    
    log "Installation completed successfully!"
    log "You can now run the system with: python3 face_recognition.py"
}

# Run main installation
main 