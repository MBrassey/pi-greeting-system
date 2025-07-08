#!/bin/bash

# Raspberry Pi Facial Recognition System Installation Script
# Optimized for Raspberry Pi 5 OS

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

# Function to fix dpkg
fix_dpkg() {
    log "Fixing dpkg state..."
    
    # Stop services that might interfere
    systemctl stop apt-daily.service apt-daily-upgrade.service || true
    systemctl kill --kill-who=all apt-daily.service apt-daily-upgrade.service || true
    
    # Kill any existing package processes
    killall -9 apt apt-get dpkg 2>/dev/null || true
    
    # Remove problematic files
    rm -rf /var/lib/dpkg/updates/*
    rm -rf /var/lib/apt/lists/partial/*
    rm -f /var/lib/dpkg/lock*
    rm -f /var/lib/apt/lists/lock
    rm -f /var/cache/apt/archives/lock
    
    # Recreate dpkg state directory
    mkdir -p /var/lib/dpkg/updates
    mkdir -p /var/lib/apt/lists/partial
    
    # Fix ssh.list issue
    mkdir -p /var/lib/dpkg/info
    echo "" > /var/lib/dpkg/info/ssh.list
    
    # Reconfigure dpkg
    dpkg --configure -a || true
    
    # Clean and update
    apt-get clean
    apt-get update --fix-missing
}

# Function to install system dependencies
install_system_deps() {
    log "Installing system dependencies..."
    
    # Fix dpkg first
    fix_dpkg
    
    # Update system first
    DEBIAN_FRONTEND=noninteractive apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
    
    # Remove potentially conflicting packages
    DEBIAN_FRONTEND=noninteractive apt-get remove -y \
        python3-numpy \
        python3-opencv \
        python3-dlib \
        || true
    
    # Install dependencies one at a time
    packages=(
        "python3-dev"
        "python3-pip"
        "python3-setuptools"
        "python3-pil"
        "python3-yaml"
        "python3-psutil"
        "cmake"
        "build-essential"
        "libopenblas-dev"
        "liblapack-dev"
        "libjpeg-dev"
        "libatlas-base-dev"
        "v4l-utils"
        "espeak"
        "git"
        "python3-opencv"
    )
    
    for package in "${packages[@]}"; do
        log "Installing $package..."
        DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$package"
        if [ $? -ne 0 ]; then
            fix_dpkg
            DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$package"
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
    
    # Update pip with break-system-packages flag
    python3 -m pip install --upgrade pip --break-system-packages
    
    # Install numpy first with specific version
    log "Installing numpy..."
    python3 -m pip install --no-cache-dir 'numpy>=1.24.0,<2.0.0' --break-system-packages
    
    # Install dlib
    log "Installing dlib..."
    python3 -m pip install --no-cache-dir dlib --break-system-packages
    
    # Install face_recognition
    log "Installing face_recognition..."
    python3 -m pip install --no-cache-dir face_recognition --break-system-packages
    
    # Install other packages
    log "Installing additional packages..."
    python3 -m pip install --no-cache-dir \
        pyttsx3 \
        Flask \
        cryptography \
        --break-system-packages
}

# Function to verify Python packages
verify_python_packages() {
    log "Verifying Python packages..."
    
    # Test numpy version first
    if python3 -c "import numpy; print(numpy.__version__)" 2>/dev/null; then
        info "NumPy version: $(python3 -c 'import numpy; print(numpy.__version__)')"
    else
        error "NumPy not properly installed"
    fi
    
    # Test OpenCV
    if python3 -c "import cv2; print(cv2.__version__)" 2>/dev/null; then
        info "OpenCV version: $(python3 -c 'import cv2; print(cv2.__version__)')"
    else
        error "OpenCV not properly installed"
    fi
    
    # Test other packages
    packages=("dlib" "face_recognition" "pyttsx3" "flask" "yaml")
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

# Function to create start script
create_start_script() {
    log "Creating start script..."
    
    cat > start-facial-recognition << 'EOF'
#!/bin/bash

# Set display
export DISPLAY=:0
export XAUTHORITY=/home/$USER/.Xauthority

# Change to installation directory
cd "$(dirname "$0")"

# Fix video permissions if needed
for device in /dev/video*; do
    if [ -e "$device" ]; then
        sudo chmod 666 "$device"
    fi
done

# Run the facial recognition system
python3 face_recognition.py
EOF
    
    chmod +x start-facial-recognition
    chown $SUDO_USER:$SUDO_USER start-facial-recognition
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
    log "Starting installation for Raspberry Pi 5..."
    
    # Check if running as root
    check_root
    
    # Fix dpkg state first
    fix_dpkg
    
    # Install system dependencies
    install_system_deps
    
    # Install Python packages
    install_python_packages
    
    # Create directory structure
    create_directories
    
    # Set up configuration
    setup_config
    
    # Create start script
    create_start_script
    
    # Verify camera
    verify_camera || true
    
    # Final verification
    if verify_python_packages; then
        log "Installation completed successfully!"
        log "You can now run the system with: ./start-facial-recognition"
    else
        warning "Installation completed with some package verification failures"
        log "The system may still work, but some features might be limited"
    fi
}

# Run main installation
main 