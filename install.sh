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
    
    # Kill any package processes
    pkill -9 dpkg apt apt-get 2>/dev/null || true
    
    # Remove all locks and temporary files
    rm -f /var/lib/dpkg/lock* /var/lib/apt/lists/lock /var/cache/apt/archives/lock
    rm -rf /var/lib/dpkg/updates/* /var/lib/apt/lists/* /var/cache/apt/archives/partial/*
    
    # Create required directories
    mkdir -p /var/lib/dpkg/updates
    mkdir -p /var/lib/apt/lists/partial
    mkdir -p /var/cache/apt/archives/partial
    mkdir -p /var/lib/dpkg/info
    
    # Fix ssh.list
    touch /var/lib/dpkg/status
    touch /var/lib/dpkg/available
    echo "" > /var/lib/dpkg/info/ssh.list
    chmod 644 /var/lib/dpkg/info/ssh.list
    
    # Fix package system
    dpkg --configure -a || true
    apt-get clean
    apt-get update --fix-missing
}

# Function to install system dependencies
install_system_deps() {
    log "Installing system dependencies..."
    
    # Fix dpkg first
    fix_dpkg
    
    # Update system
    DEBIAN_FRONTEND=noninteractive apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
    
    # Install build dependencies first
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        build-essential \
        cmake \
        pkg-config \
        python3-dev \
        python3-pip \
        python3-setuptools \
        || true
    
    # Install face recognition dependencies
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        libopenblas-dev \
        liblapack-dev \
        libatlas-base-dev \
        libjpeg-dev \
        || true
    
    # Install Python packages via apt
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        python3-numpy \
        python3-opencv \
        python3-pil \
        python3-yaml \
        python3-psutil \
        python3-flask \
        python3-pyttsx3 \
        v4l-utils \
        espeak \
        || true

    # Install dlib from source (more reliable)
    log "Installing dlib from source..."
    if [ ! -d "dlib" ]; then
        git clone https://github.com/davisking/dlib.git
    fi
    cd dlib
    python3 setup.py install --no
    cd ..
    rm -rf dlib

    # Install face_recognition from source
    log "Installing face_recognition from source..."
    if [ ! -d "face_recognition" ]; then
        git clone https://github.com/ageitgey/face_recognition.git
    fi
    cd face_recognition
    python3 setup.py install
    cd ..
    rm -rf face_recognition

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

# Function to verify Python packages
verify_python_packages() {
    log "Verifying Python packages..."
    
    # Test imports
    packages=(
        "cv2"
        "numpy"
        "PIL"
        "yaml"
        "face_recognition"
        "flask"
        "pyttsx3"
    )
    
    failed=0
    for package in "${packages[@]}"; do
        if ! python3 -c "import ${package}" 2>/dev/null; then
            error "Failed to import ${package}"
            failed=1
        else
            info "${package} imported successfully"
        fi
    done
    
    return $failed
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
  type: 'usb'
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
    
    # Check for video devices directly since v4l2-ctl might not be available
    if ! ls /dev/video* >/dev/null 2>&1; then
        warning "No video devices found - please check camera connection"
        return 1
    fi
    
    info "Camera verification successful"
    info "Found video devices:"
    ls -l /dev/video*
    return 0
}

# Main installation function
main() {
    log "Starting installation for Raspberry Pi 5..."
    
    # Check if running as root
    check_root
    
    # Fix dpkg state
    fix_dpkg
    
    # Install system dependencies
    install_system_deps
    
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
        log "Please try running: sudo apt-get install -f"
        log "Then run this script again"
    fi
}

# Run main installation
main 