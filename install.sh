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

# Function to detect camera type
detect_camera_type() {
    log "Detecting camera type..."
    
    # Force USB camera detection with multiple retries
    local max_attempts=5
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        log "USB camera detection attempt $attempt/$max_attempts..."
        
        # Ensure USB video module is loaded
        if ! lsmod | grep -q "uvcvideo"; then
            log "Loading USB video driver..."
            sudo modprobe uvcvideo
            sleep 2
        fi
        
        # Force device node permissions
        for dev in /dev/video*; do
            if [ -e "$dev" ]; then
                sudo chmod 666 "$dev"
            fi
        done
        
        # Check using multiple methods
        local usb_camera_found=0
        
        # Method 1: Direct device check
        if [ -e "/dev/video0" ] || [ -e "/dev/video1" ]; then
            usb_camera_found=1
            export CAMERA_DEV="/dev/video0"
        fi
        
        # Method 2: V4L2 check
        if v4l2-ctl --list-devices 2>/dev/null | grep -q "video"; then
            usb_camera_found=1
            export CAMERA_DEV=$(v4l2-ctl --list-devices 2>/dev/null | grep "/dev/video" | head -n1 | xargs)
        fi
        
        # Method 3: USB device check
        if lsusb | grep -qi "camera\|webcam\|uvc"; then
            usb_camera_found=1
            # Find corresponding video device if not already found
            if [ -z "$CAMERA_DEV" ]; then
                export CAMERA_DEV=$(ls /dev/video* | head -n1)
            fi
        fi
        
        if [ $usb_camera_found -eq 1 ]; then
            info "USB webcam detected"
            export CAMERA_TYPE="usb"
            info "Using camera device: $CAMERA_DEV"
            return 0
        fi
        
        log "Camera not detected, retrying after system adjustments..."
        
        # Try to fix common issues
        sudo rmmod uvcvideo || true
        sudo rmmod videobuf2_core || true
        sleep 1
        sudo modprobe uvcvideo
        sudo modprobe videobuf2_core
        sleep 2
        
        attempt=$((attempt + 1))
    done
    
    error "Could not detect USB camera after $max_attempts attempts"
    # Print diagnostic information
    log "=== Diagnostic Information ==="
    echo "USB Devices:"
    lsusb
    echo -e "\nVideo Devices:"
    ls -l /dev/video* 2>/dev/null || echo "No video devices found"
    echo -e "\nLoaded Modules:"
    lsmod | grep -E "uvcvideo|videobuf|videodev"
    echo -e "\nV4L2 Devices:"
    v4l2-ctl --list-devices 2>/dev/null
    echo -e "\nSystem Messages:"
    dmesg | grep -i "uvc\|video\|camera" | tail -n 20
    return 1
}

# Function to test USB camera
test_usb_camera() {
    local device=$1
    log "Testing USB camera on $device..."
    
    # Ensure OpenCV is installed
    if ! python3 -c "import cv2" 2>/dev/null; then
        log "Installing OpenCV..."
        sudo apt-get update
        sudo apt-get install -y python3-opencv
    fi
    
    # Create test script for USB camera
    local test_script="/tmp/test_usb_camera.py"
    cat > "$test_script" << 'EOF'
import cv2
import sys
import json
import time
import os

def test_camera():
    success = False
    last_error = None
    
    # Try different methods and indices
    methods = [
        lambda idx: cv2.VideoCapture(idx),  # Index-based
        lambda idx: cv2.VideoCapture(f"/dev/video{idx}"),  # Direct device
        lambda idx: cv2.VideoCapture(f"v4l2:///dev/video{idx}")  # V4L2 explicit
    ]
    
    for method in methods:
        for idx in range(10):  # Try indices 0-9
            try:
                print(f"Trying camera method {methods.index(method)+1}/3, index {idx}", file=sys.stderr)
                cap = method(idx)
                
                if not cap.isOpened():
                    continue
                
                # Try multiple times to get a frame
                for attempt in range(10):
                    ret, frame = cap.read()
                    if ret and frame is not None and frame.size > 0:
                        # Get camera info
                        width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
                        height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
                        fps = cap.get(cv2.CAP_PROP_FPS)
                        
                        # Save test image
                        cv2.imwrite('camera_test_initial.jpg', frame)
                        
                        # Save camera info
                        camera_info = {
                            "type": "USB",
                            "index": idx,
                            "method": methods.index(method) + 1,
                            "resolution": f"{width}x{height}",
                            "fps": fps,
                            "device": f"/dev/video{idx}",
                            "attempts_needed": attempt + 1
                        }
                        
                        with open('camera_info.json', 'w') as f:
                            json.dump(camera_info, f, indent=2)
                        
                        cap.release()
                        print(f"Successfully captured image using method {methods.index(method)+1}, index {idx}", file=sys.stderr)
                        return True
                    
                    time.sleep(0.5)  # Wait between attempts
                cap.release()
                
            except Exception as e:
                last_error = str(e)
                continue
    
    if last_error:
        print(f"All attempts failed. Last error: {last_error}", file=sys.stderr)
    return False

if __name__ == "__main__":
    # Try multiple times
    max_attempts = 5
    for attempt in range(max_attempts):
        print(f"Camera test attempt {attempt + 1}/{max_attempts}", file=sys.stderr)
        if test_camera():
            sys.exit(0)
        time.sleep(1)
    sys.exit(1)
EOF
    
    # Make multiple attempts to test the camera
    local max_attempts=3
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        log "Camera test attempt $attempt/$max_attempts..."
        
        # Ensure device permissions
        sudo chmod 666 "$device"
        
        # Run test with debug output
        if python3 "$test_script" 2>&1; then
            info "Camera test successful!"
            rm -f "$test_script"
            return 0
        fi
        
        log "Test failed, retrying after adjustments..."
        
        # Try to fix common issues
        sudo v4l2-ctl --device="$device" --all >/dev/null 2>&1 || true
        sleep 2
        
        attempt=$((attempt + 1))
    done
    
    error "Camera test failed after $max_attempts attempts"
    # Show device information
    log "=== Device Information ==="
    v4l2-ctl --device="$device" --all || true
    v4l2-ctl --device="$device" --list-formats-ext || true
    
    rm -f "$test_script"
    return 1
}

# Function to test Pi Camera
test_pi_camera() {
    log "Testing Pi Camera..."
    
    # Create test script for Pi Camera
    local test_script="/tmp/test_pi_camera.py"
    cat > "$test_script" << 'EOF'
from picamera2 import Picamera2
import time
import json
import sys

def test_camera():
    try:
        picam2 = Picamera2()
        
        # Get camera info
        camera_info = {
            "type": "Pi Camera",
            "model": picam2.camera.id,
            "modes": picam2.camera.modes
        }
        
        # Configure camera
        config = picam2.create_still_configuration()
        picam2.configure(config)
        
        # Start camera with timeout
        picam2.start()
        time.sleep(2)
        
        # Capture test image
        picam2.capture_file("camera_test_initial.jpg")
        picam2.close()
        
        # Save camera info
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
    
    # Run Pi camera test
    if ! python3 "$test_script"; then
        error "Pi camera test failed"
        rm -f "$test_script"
        return 1
    fi
    
    rm -f "$test_script"
    return 0
}

# Function to configure camera
configure_camera() {
    log "Configuring camera system..."
    
    # Detect camera type first
    if ! detect_camera_type; then
        error "No camera detected"
        return 1
    fi
    
    case $CAMERA_TYPE in
        "usb")
            log "Configuring USB camera..."
            # Install USB camera dependencies
            sudo apt-get install -y v4l-utils guvcview || true
            ;;
            
        "imx519"|"picamera")
            log "Configuring Pi Camera..."
            # Backup config.txt
            if [ ! -f "/boot/config.txt.backup" ]; then
                sudo cp /boot/config.txt /boot/config.txt.backup
            fi
            
            # Remove existing camera config
            sudo sed -i '/^start_x=/d' /boot/config.txt
            sudo sed -i '/^camera_auto_detect=/d' /boot/config.txt
            sudo sed -i '/^dtoverlay=imx519/d' /boot/config.txt
            sudo sed -i '/^gpu_mem=/d' /boot/config.txt
            sudo sed -i '/^dtparam=i2c_arm=/d' /boot/config.txt
            
            # Add new camera config
            {
                echo ""
                echo "# Camera configuration"
                echo "start_x=1"
                echo "camera_auto_detect=1"
                [ "$CAMERA_TYPE" = "imx519" ] && echo "dtoverlay=imx519"
                echo "gpu_mem=256"
                echo "dtparam=i2c_arm=on"
            } | sudo tee -a /boot/config.txt
            
            # Enable interfaces
            if command -v raspi-config >/dev/null 2>&1; then
                sudo raspi-config nonint do_camera 0
                sudo raspi-config nonint do_i2c 0
            fi
            
            # Setup camera tuning if needed
            [ "$CAMERA_TYPE" = "imx519" ] && setup_camera_tuning
            ;;
    esac
    
    return 0
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
    
    # Test based on camera type
    case $CAMERA_TYPE in
        "usb")
            test_usb_camera "/dev/video0"
            ;;
        "imx519"|"picamera")
            test_pi_camera
            ;;
    esac
    
    # Verify test results
    if [ ! -f "camera_test_initial.jpg" ]; then
        error "Camera test failed - no test image captured"
        return 1
    fi
    
    if [ -f "camera_info.json" ]; then
        info "Camera test successful"
        info "Test image saved as: camera_test_initial.jpg"
        echo "Camera information:"
        cat camera_info.json
    fi
    
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