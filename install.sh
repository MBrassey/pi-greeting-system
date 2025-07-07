#!/bin/bash

# Raspberry Pi Facial Recognition System Installation Script
# Handles complete system installation and dependency management

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

# Function to check command existence
check_command() {
    if ! command -v "$1" &> /dev/null; then
        return 1
    fi
    return 0
}

# Function to fix package issues
fix_packages() {
    log "Checking and fixing package dependencies..."
    
    # Try to fix broken packages
    sudo apt-get update --fix-missing
    sudo dpkg --configure -a
    sudo apt-get install -f -y
    sudo apt-get --fix-broken install -y
    
    # Clean up any mess
    sudo apt-get autoremove -y
    sudo apt-get clean
    
    # Update package lists again
    sudo apt-get update
}

# Function to check Pi model
check_pi_model() {
    if [ ! -f "/proc/device-tree/model" ]; then
        warning "Cannot determine Raspberry Pi model, continuing anyway..."
        export PI_MODEL=4
        return
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
        warning "Unknown Raspberry Pi model, continuing anyway..."
        export PI_MODEL=4
    fi
}

# Function to check and update system
update_system() {
    log "Updating system packages..."
    
    # Fix any existing issues first
    fix_packages
    
    # Try to upgrade the system
    if ! sudo apt-get upgrade -y; then
        warning "System upgrade had issues, attempting to fix..."
        fix_packages
        sudo apt-get upgrade -y || true
    fi
    
    # Install basic utilities
    sudo apt-get install -y git wget curl bc build-essential || true
    
    # Fix any issues that might have come up
    fix_packages
}

# Function to install camera dependencies
install_camera_deps() {
    log "Installing camera dependencies..."
    
    # Remove conflicting packages
    sudo apt-get remove -y python3-picamera || true
    
    # Create a temporary file to track installation progress
    local progress_file=$(mktemp)
    echo "0" > "$progress_file"
    
    # Function to install packages with retry
    install_with_retry() {
        local packages="$1"
        local max_attempts=3
        local attempt=1
        
        while [ $attempt -le $max_attempts ]; do
            if sudo apt-get install -y --no-install-recommends $packages; then
                return 0
            fi
            warning "Attempt $attempt failed, trying to fix packages..."
            fix_packages
            attempt=$((attempt + 1))
        done
        return 1
    }
    
    # Install packages in groups with progress tracking
    local total_steps=4
    local current_step=1
    
    # Step 1: Core utilities
    log "[$current_step/$total_steps] Installing core utilities..."
    install_with_retry "i2c-tools libraspberrypi-bin raspi-config"
    echo $((current_step * 100 / total_steps)) > "$progress_file"
    current_step=$((current_step + 1))
    
    # Step 2: Camera libraries
    log "[$current_step/$total_steps] Installing camera libraries..."
    install_with_retry "libcamera0 python3-libcamera python3-picamera2"
    echo $((current_step * 100 / total_steps)) > "$progress_file"
    current_step=$((current_step + 1))
    
    # Step 3: Camera applications
    log "[$current_step/$total_steps] Installing camera applications..."
    install_with_retry "libcamera-tools libcamera-apps-lite v4l-utils"
    echo $((current_step * 100 / total_steps)) > "$progress_file"
    current_step=$((current_step + 1))
    
    # Step 4: Additional dependencies
    log "[$current_step/$total_steps] Installing additional dependencies..."
    install_with_retry "python3-opencv python3-numpy"
    echo $((current_step * 100 / total_steps)) > "$progress_file"
    
    # Final verification
    if ! dpkg -l | grep -q "libcamera0"; then
        error "Critical camera packages not installed"
        rm "$progress_file"
        return 1
    fi
    
    # Cleanup
    rm "$progress_file"
    return 0
}

# Function to verify camera hardware
verify_camera_hardware() {
    log "Verifying camera hardware connection..."
    
    # Check if camera module is physically detected
    if ! vcgencmd get_camera | grep -q "detected=1"; then
        error "Camera hardware not detected by system"
        error "Please check:"
        echo "  1. Camera ribbon cable is properly seated at both ends"
        echo "  2. Cable is oriented correctly (blue side facing away from contacts)"
        echo "  3. Cable is not damaged"
        echo "  4. Camera module power connections are good"
        return 1
    fi
    
    # Give hardware time to initialize
    log "Camera detected, waiting for hardware initialization..."
    sleep 5
    
    # Check I2C communication
    local i2c_bus
    if [ "$PI_MODEL" = "5" ]; then
        i2c_bus=10
    else
        i2c_bus=7
    fi
    
    # Try multiple times to detect camera on I2C
    local max_attempts=3
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        log "Checking camera I2C communication (attempt $attempt/$max_attempts)..."
        if i2cdetect -y $i2c_bus | grep -q "1a\|36"; then
            info "Camera I2C communication verified"
            return 0
        fi
        sleep 2
        attempt=$((attempt + 1))
    done
    
    error "Failed to establish I2C communication with camera"
    error "This might indicate a power issue or damaged module"
    return 1
}

# Function to configure camera
configure_camera() {
    log "Configuring camera system..."
    
    # First verify camera hardware
    if ! verify_camera_hardware; then
        return 1
    fi
    
    # Backup config.txt if it hasn't been backed up in this session
    if [ ! -f "/boot/config.txt.backup" ]; then
        sudo cp /boot/config.txt /boot/config.txt.backup
    fi
    
    # Remove any existing camera configuration
    sudo sed -i '/^start_x=/d' /boot/config.txt
    sudo sed -i '/^camera_auto_detect=/d' /boot/config.txt
    sudo sed -i '/^dtoverlay=imx519/d' /boot/config.txt
    sudo sed -i '/^gpu_mem=/d' /boot/config.txt
    sudo sed -i '/^dtparam=i2c_arm=/d' /boot/config.txt
    sudo sed -i '/^dtparam=i2c_vc=/d' /boot/config.txt
    
    # Add fresh configuration
    log "Adding camera configuration..."
    {
        echo ""
        echo "# Camera configuration"
        echo "start_x=1"
        echo "camera_auto_detect=1"
        echo "dtoverlay=imx519"
        echo "gpu_mem=256"
        echo "dtparam=i2c_arm=on"
        echo "dtparam=i2c_vc=on"
    } | sudo tee -a /boot/config.txt
    
    # Enable interfaces
    log "Enabling required interfaces..."
    if command -v raspi-config >/dev/null 2>&1; then
        sudo raspi-config nonint do_camera 0
        sudo raspi-config nonint do_i2c 0
    fi
    
    # Set up camera tuning
    setup_camera_tuning
    
    # Force reload camera module
    log "Reloading camera module..."
    sudo rmmod v4l2_common || true
    sudo rmmod bcm2835_v4l2 || true
    sudo rmmod videobuf2_common || true
    sudo modprobe bcm2835_v4l2
    sleep 2
    
    return 0
}

# Function to set up camera tuning
setup_camera_tuning() {
    log "Setting up camera tuning..."
    
    sudo mkdir -p /usr/share/libcamera/ipa/raspberrypi
    
    # Only create tuning file if it doesn't exist or is different
    local tuning_file="/usr/share/libcamera/ipa/raspberrypi/imx519.json"
    local temp_file=$(mktemp)
    
    cat > "$temp_file" << 'EOF'
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
    
    if [ ! -f "$tuning_file" ] || ! cmp -s "$temp_file" "$tuning_file"; then
        sudo cp "$temp_file" "$tuning_file"
    fi
    
    rm "$temp_file"
}

# Function to test camera
test_camera() {
    log "Testing camera configuration..."
    
    # Wait for camera device
    log "Waiting for camera device initialization..."
    local timeout=10
    local count=0
    while [ $count -lt $timeout ]; do
        if [ -e "/dev/video0" ]; then
            break
        fi
        sleep 1
        count=$((count + 1))
    done
    
    if [ ! -e "/dev/video0" ]; then
        error "Camera device not found after waiting"
        return 1
    fi
    
    # Create test script
    local test_script="/tmp/test_camera.py"
    cat > "$test_script" << 'EOF'
from picamera2 import Picamera2
import time
import json
import sys

def test_camera():
    try:
        # Initialize with longer timeout
        picam2 = Picamera2()
        time.sleep(2)  # Wait for initialization
        
        # Get camera info first
        camera_info = {
            "model": picam2.camera.id,
            "modes": picam2.camera.modes
        }
        
        # Log camera info
        print("Camera Info:", file=sys.stderr)
        print(f"Model: {camera_info['model']}", file=sys.stderr)
        print(f"Available Modes: {len(camera_info['modes'])}", file=sys.stderr)
        
        # Test configuration
        config = picam2.create_still_configuration(
            main={"size": (4656, 3496)},
            lores={"size": (1920, 1080)},
            display="lores"
        )
        picam2.configure(config)
        
        # Start camera with timeout
        picam2.start()
        time.sleep(3)  # Extended warm-up
        
        # Try to capture
        picam2.capture_file("camera_test_full.jpg")
        picam2.close()
        
        with open("camera_info.json", "w") as f:
            json.dump(camera_info, f, indent=2)
        
        return True
    except Exception as e:
        print(f"Camera Test Error: {str(e)}", file=sys.stderr)
        return False

if __name__ == "__main__":
    success = test_camera()
    sys.exit(0 if success else 1)
EOF
    
    # Run test with debug output
    log "Running camera test..."
    export LIBCAMERA_LOG_LEVELS=0
    if ! python3 "$test_script" 2>&1; then
        error "Camera test failed"
        # Try to gather diagnostic information
        log "Gathering diagnostic information..."
        echo "I2C Devices:"
        i2cdetect -y 7 || i2cdetect -y 10 || true
        echo "Video Devices:"
        ls -l /dev/video* || true
        echo "dmesg output:"
        dmesg | grep -i "camera\|v4l\|video" | tail -n 20 || true
        rm -f "$test_script"
        return 1
    fi
    
    # Verify results
    if [ ! -f "camera_test_full.jpg" ]; then
        error "Test image capture failed"
        rm -f "$test_script"
        return 1
    fi
    
    # Cleanup
    rm -f "$test_script"
    mv camera_test_full.jpg camera_test_initial.jpg
    
    info "Camera test successful"
    info "Test image saved as: camera_test_initial.jpg"
    return 0
}

# Function to install Python dependencies
install_python_deps() {
    log "Installing Python dependencies..."
    
    # Install Python packages
    sudo apt-get install -y \
        python3-dev \
        python3-pip \
        python3-venv \
        python3-wheel \
        python3-picamera2 \
        || fix_packages
    
    # Create virtual environment if it doesn't exist
    if [ ! -d "venv" ]; then
        python3 -m venv venv
    fi
    
    # Activate and upgrade pip
    source venv/bin/activate
    pip install --upgrade pip wheel setuptools
    
    # Install required packages with retry
    local packages=(
        "numpy"
        "opencv-python"
        "picamera2"
        "face-recognition"
        "dlib"
        "Pillow"
        "pyttsx3"
        "Flask"
        "PyYAML"
    )
    
    for package in "${packages[@]}"; do
        log "Installing $package..."
        if ! pip install "$package"; then
            warning "Failed to install $package, retrying..."
            pip install --no-cache-dir "$package" || true
        fi
    done
    
    deactivate
}

# Function to install audio dependencies
install_audio_deps() {
    log "Installing audio dependencies..."
    
    sudo apt-get install -y \
        espeak \
        alsa-utils \
        pulseaudio \
        || fix_packages
}

# Function to create directory structure
create_directories() {
    log "Creating directory structure..."
    
    local dirs=(
        "data/known_faces"
        "data/unknown_faces"
        "data/logs"
        "data/backups"
        "templates"
        "static/faces"
        "ssl"
    )
    
    for dir in "${dirs[@]}"; do
        mkdir -p "$dir"
        chmod 755 "$dir"
    done
}

# Main installation sequence
main() {
    log "Starting installation..."
    
    # System checks and setup
    check_pi_model
    update_system
    
    # Camera setup
    if ! install_camera_deps; then
        error "Camera dependency installation failed"
        fix_packages
        if ! install_camera_deps; then
            error "Camera setup failed after retry"
            exit 1
        fi
    fi
    
    configure_camera
    
    # Test camera setup
    if ! test_camera; then
        warning "Initial camera test failed, attempting to fix..."
        fix_packages
        configure_camera
        if ! test_camera; then
            error "Camera setup failed after retry"
            exit 1
        fi
    fi
    
    # Additional components
    install_audio_deps
    install_python_deps
    create_directories
    
    # Set permissions
    chmod +x *.sh *.py
    
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