#!/bin/bash

# Raspberry Pi Facial Recognition System Installation Script
# Handles complete system installation and dependency management

set -e  # Exit on any error

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

# Function to check command existence
check_command() {
    if ! command -v "$1" &> /dev/null; then
        return 1
    fi
    return 0
}

# Function to check Pi model
check_pi_model() {
    if [ ! -f "/proc/device-tree/model" ]; then
        error "Cannot determine Raspberry Pi model"
        exit 1
    fi

    local model
    model=$(tr -d '\0' < /proc/device-tree/model)
    
    if [[ $model == *"Raspberry Pi 5"* ]]; then
        info "Detected Raspberry Pi 5"
        export PI_MODEL=5
    elif [[ $model == *"Raspberry Pi 4"* ]]; then
        info "Detected Raspberry Pi 4"
        export PI_MODEL=4
    else
        error "Unsupported Raspberry Pi model: $model"
        error "This system requires Raspberry Pi 4 or 5"
        exit 1
    fi
}

# Function to check OS
check_os() {
    if ! grep -q "Raspbian\|Raspberry Pi OS" /etc/os-release; then
        error "This script requires Raspberry Pi OS (Raspbian)"
        exit 1
    fi
    
    # Check if it's 64-bit
    if ! uname -m | grep -q 'aarch64\|arm64'; then
        error "64-bit OS is required for optimal performance"
        error "Please install the 64-bit version of Raspberry Pi OS"
        exit 1
    fi
}

# Function to check and update system
update_system() {
    log "Updating system packages..."
    
    # Update package lists and upgrade system
    sudo apt-get update || { error "Failed to update package lists"; exit 1; }
    sudo apt-get upgrade -y || { error "Failed to upgrade system packages"; exit 1; }
    
    # Install basic utilities
    sudo apt-get install -y \
        git wget curl bc build-essential \
        || { error "Failed to install basic utilities"; exit 1; }
}

# Function to install camera dependencies
install_camera_deps() {
    log "Installing camera dependencies..."
    
    # Remove legacy camera stack if present
    sudo apt-get remove -y python3-picamera || true
    
    # Install new camera stack
    sudo apt-get install -y \
        python3-libcamera \
        python3-picamera2 \
        python3-opencv \
        python3-numpy \
        libcamera-tools \
        libcamera-apps \
        v4l-utils \
        || { error "Failed to install camera dependencies"; exit 1; }
        
    # Install additional camera utilities
    sudo apt-get install -y \
        i2c-tools \
        libraspberrypi-bin \
        raspi-config \
        || { error "Failed to install camera utilities"; exit 1; }
}

# Function to detect IMX519 camera
detect_imx519() {
    log "Detecting Arducam IMX519 camera..."
    
    # Wait for I2C to initialize
    sleep 2
    
    local i2c_bus
    if [ "$PI_MODEL" = "5" ]; then
        i2c_bus=10
    else
        i2c_bus=7
    fi
    
    # Check for IMX519 signature on I2C bus
    if i2cdetect -y $i2c_bus | grep -q "1a"; then
        info "Arducam IMX519 camera detected"
        return 0
    else
        error "Arducam IMX519 camera not detected"
        error "Please check:"
        echo "  1. Camera ribbon cable is properly connected"
        echo "  2. Camera ribbon cable is oriented correctly"
        echo "  3. Camera ribbon cable is not damaged"
        echo "  4. Camera module is properly seated"
        return 1
    fi
}

# Function to configure camera
configure_camera() {
    log "Configuring camera system..."
    
    # Enable camera interface
    log "Enabling camera interface..."
    sudo raspi-config nonint do_camera 0
    
    # Enable I2C interface
    log "Enabling I2C interface..."
    sudo raspi-config nonint do_i2c 0
    
    # Configure boot settings
    log "Configuring boot settings..."
    
    # Backup config.txt
    sudo cp /boot/config.txt /boot/config.txt.backup
    
    # Update camera configuration
    sudo sed -i '/^camera_auto_detect/d' /boot/config.txt
    sudo sed -i '/^dtoverlay=imx519/d' /boot/config.txt
    sudo sed -i '/^dtoverlay=camera/d' /boot/config.txt
    sudo sed -i '/^gpu_mem/d' /boot/config.txt
    
    # Add IMX519 specific configuration
    echo "camera_auto_detect=1" | sudo tee -a /boot/config.txt
    echo "dtoverlay=imx519" | sudo tee -a /boot/config.txt
    echo "gpu_mem=256" | sudo tee -a /boot/config.txt
    
    # Create camera tuning file
    log "Setting up camera tuning..."
    sudo mkdir -p /usr/share/libcamera/ipa/raspberrypi
    cat > imx519.json << 'EOF'
{
    "version": 1.0,
    "target": "bcm2835-isp",
    "algorithms": {
        "rpi.agc": {
            "exposure_modes": {
                "normal": { "shutter": [100, 66666], "gain": [1.0, 8.0] }
            },
            "exposure_mode": "normal"
        },
        "rpi.awb": {
            "bayes": 1,
            "ct_curve": [
                {"x": 2500, "y": 1.2},
                {"x": 6500, "y": 1.0}
            ]
        }
    }
}
EOF
    sudo cp imx519.json /usr/share/libcamera/ipa/raspberrypi/
    rm imx519.json
}

# Function to test camera
test_camera() {
    log "Testing camera configuration..."
    
    # Create test script
    cat > test_camera.py << 'EOF'
from picamera2 import Picamera2
import time
import json

def test_camera():
    try:
        # Initialize camera
        picam2 = Picamera2()
        
        # Test full resolution capture
        config = picam2.create_still_configuration(
            main={"size": (4656, 3496)},  # Full 16MP
            lores={"size": (1920, 1080)},
            display="lores"
        )
        picam2.configure(config)
        
        # Start camera
        picam2.start()
        time.sleep(2)  # Warm-up
        
        # Capture test image
        picam2.capture_file("camera_test_full.jpg")
        
        # Get camera info
        camera_info = {
            "model": picam2.camera.id,
            "resolution": config["main"]["size"],
            "modes": picam2.camera.modes
        }
        
        with open("camera_info.json", "w") as f:
            json.dump(camera_info, f, indent=2)
        
        picam2.close()
        return True
    except Exception as e:
        print(f"Error: {e}")
        return False

if __name__ == "__main__":
    success = test_camera()
    exit(0 if success else 1)
EOF
    
    # Run camera test
    log "Running camera test..."
    if ! python3 test_camera.py; then
        error "Camera test failed"
        error "Please check camera connection and try again"
        return 1
    fi
    
    # Verify test image
    if [ ! -f "camera_test_full.jpg" ]; then
        error "Test image capture failed"
        return 1
    fi
    
    # Check camera info
    if [ -f "camera_info.json" ]; then
        if ! grep -q "imx519" camera_info.json; then
            warning "Camera model verification failed"
            return 1
        fi
    else
        warning "Camera information not available"
        return 1
    fi
    
    # Cleanup test files
    rm -f test_camera.py camera_info.json
    mv camera_test_full.jpg camera_test_initial.jpg
    
    info "Camera test successful"
    info "Test image saved as: camera_test_initial.jpg"
    return 0
}

# Function to install Python dependencies
install_python_deps() {
    log "Installing Python dependencies..."
    
    # Install Python development packages
    sudo apt-get install -y \
        python3-dev \
        python3-pip \
        python3-venv \
        python3-wheel \
        python3-picamera2 \
        || { error "Failed to install Python packages"; exit 1; }
    
    # Create virtual environment
    python3 -m venv venv
    source venv/bin/activate
    
    # Upgrade pip
    pip install --upgrade pip wheel setuptools
    
    # Install required Python packages
    pip install \
        numpy \
        opencv-python \
        picamera2 \
        face-recognition \
        dlib \
        Pillow \
        pyttsx3 \
        Flask \
        PyYAML \
        || { error "Failed to install Python packages"; exit 1; }
    
    deactivate
}

# Function to install audio dependencies
install_audio_deps() {
    log "Installing audio dependencies..."
    
    sudo apt-get install -y \
        espeak \
        alsa-utils \
        pulseaudio \
        || { error "Failed to install audio packages"; exit 1; }
}

# Function to test audio
test_audio() {
    log "Testing audio configuration..."
    
    # Check audio devices
    if ! aplay -l | grep -q "card"; then
        warning "No audio devices detected"
        return 1
    fi
    
    # Test audio output
    if ! timeout 2s speaker-test -t wav -c 2 >/dev/null 2>&1; then
        warning "Audio test failed"
        return 1
    fi
    
    info "Audio test successful"
    return 0
}

# Function to create directory structure
create_directories() {
    log "Creating directory structure..."
    
    mkdir -p data/{known_faces,unknown_faces,logs,backups}
    mkdir -p templates static/faces ssl
    chmod -R 755 data templates static ssl
}

# Main installation sequence
main() {
    log "Starting installation..."
    
    # System checks
    check_pi_model
    check_os
    update_system
    
    # Camera setup
    install_camera_deps
    
    # Detect and configure IMX519
    if ! detect_imx519; then
        error "IMX519 camera detection failed"
        error "Please check camera connection and try again"
        exit 1
    fi
    
    configure_camera
    
    # Test camera setup
    if ! test_camera; then
        error "Camera setup verification failed"
        error "Please check the error messages above and try again"
        exit 1
    fi
    
    # Audio setup
    install_audio_deps
    test_audio
    
    # Python setup
    install_python_deps
    
    # Directory setup
    create_directories
    
    # Set permissions
    chmod +x *.sh
    chmod +x *.py
    
    log "Installation completed successfully!"
    echo ""
    echo -e "${GREEN}=== System Status ===${NC}"
    echo "Camera: Arducam IMX519 16MP ($(test -f camera_test_initial.jpg && echo "Verified" || echo "Not verified"))"
    echo "Audio: $(aplay -l | grep -c "card" || echo "Not detected")"
    echo "Python: $(python3 --version)"
    echo ""
    echo -e "${GREEN}=== Next Steps ===${NC}"
    echo "1. Reboot system:    sudo reboot"
    echo "2. After reboot:"
    echo "   - Run test:       ./test_camera.sh"
    echo "   - Start system:   ./start.sh"
    echo ""
    echo -e "${YELLOW}Note: System reboot required to apply all changes${NC}"
    echo -e "${YELLOW}Note: Check camera_test_initial.jpg to verify camera quality${NC}"
}

# Run main installation
main 