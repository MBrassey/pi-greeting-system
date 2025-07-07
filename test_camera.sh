#!/bin/bash

# Camera Test Script for Raspberry Pi Facial Recognition System
# Tests camera functionality and provides diagnostic information

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

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   error "This script should not be run as root"
   exit 1
fi

# Check for virtual environment
if [ ! -d "venv" ]; then
    error "Virtual environment not found. Please run install.sh first."
    exit 1
fi

# Activate virtual environment
source venv/bin/activate

# Function to test USB camera
test_usb_camera() {
    log "Testing USB camera..."
    
    # Check for video devices
    if ! ls /dev/video* &> /dev/null; then
        error "No video devices found"
        info "Please check:"
        echo "  1. Camera is properly connected"
        echo "  2. Camera is supported by Linux"
        echo "  3. Required drivers are installed"
        return 1
    fi
    
    # List available devices
    info "Available video devices:"
    ls -l /dev/video*
    
    # Test camera access
    info "Testing camera access..."
    python3 - << EOF
import cv2
import time
import sys

try:
    # Try to open camera
    cap = cv2.VideoCapture(0)
    if not cap.isOpened():
        raise Exception("Could not open camera")
    
    # Get camera info
    width = cap.get(cv2.CAP_PROP_FRAME_WIDTH)
    height = cap.get(cv2.CAP_PROP_FRAME_HEIGHT)
    fps = cap.get(cv2.CAP_PROP_FPS)
    
    print(f"Camera opened successfully")
    print(f"Resolution: {width}x{height}")
    print(f"FPS: {fps}")
    
    # Try to read a frame
    ret, frame = cap.read()
    if not ret:
        raise Exception("Could not read frame")
    
    # Save test image
    cv2.imwrite('camera_test.jpg', frame)
    print("Test image saved as camera_test.jpg")
    
    # Release camera
    cap.release()
    sys.exit(0)
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
EOF
    
    return $?
}

# Function to test Pi Camera
test_pi_camera() {
    log "Testing Raspberry Pi Camera..."
    
    # Check if Pi Camera is enabled
    if ! vcgencmd get_camera | grep -q "supported=1 detected=1"; then
        error "Pi Camera not detected"
        info "Please check:"
        echo "  1. Camera is properly connected"
        echo "  2. Camera is enabled in raspi-config"
        echo "  3. Ribbon cable is properly seated"
        return 1
    fi
    
    # Test camera access
    info "Testing camera access..."
    python3 - << EOF
import sys
try:
    from picamera2 import Picamera2
    picam2 = Picamera2()
    
    # Get camera info
    config = picam2.create_preview_configuration()
    picam2.configure(config)
    
    # Start camera
    picam2.start()
    
    # Get camera info
    print("Camera info:")
    print(f"Resolution: {config['main']['size']}")
    
    # Capture test image
    picam2.capture_file("camera_test.jpg")
    print("Test image saved as camera_test.jpg")
    
    # Stop camera
    picam2.stop()
    sys.exit(0)
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
EOF
    
    return $?
}

# Function to check image quality
check_image_quality() {
    if [ ! -f "camera_test.jpg" ]; then
        error "Test image not found"
        return 1
    }
    
    info "Analyzing image quality..."
    python3 - << EOF
import cv2
import numpy as np
import sys

try:
    # Read image
    img = cv2.imread('camera_test.jpg')
    if img is None:
        raise Exception("Could not read test image")
    
    # Check resolution
    height, width = img.shape[:2]
    print(f"Image resolution: {width}x{height}")
    
    if width < 640 or height < 480:
        print("Warning: Resolution is below recommended minimum (640x480)")
    
    # Check brightness
    brightness = np.mean(img)
    print(f"Average brightness: {brightness:.1f}/255")
    
    if brightness < 50:
        print("Warning: Image is too dark")
    elif brightness > 200:
        print("Warning: Image is too bright")
    
    # Check blur
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    blur_value = cv2.Laplacian(gray, cv2.CV_64F).var()
    print(f"Blur metric: {blur_value:.1f}")
    
    if blur_value < 100:
        print("Warning: Image may be too blurry")
    
    # Check for faces
    face_cascade = cv2.CascadeClassifier(cv2.data.haarcascades + 'haarcascade_frontalface_default.xml')
    faces = face_cascade.detectMultiScale(gray, 1.3, 5)
    print(f"Faces detected: {len(faces)}")
    
    sys.exit(0)
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
EOF
    
    return $?
}

# Main test sequence
log "Starting camera tests..."

# Determine camera type
if [ -e "/dev/video0" ]; then
    info "USB camera detected"
    test_usb_camera
    camera_result=$?
else
    info "Checking for Pi Camera"
    test_pi_camera
    camera_result=$?
fi

# Check results
if [ $camera_result -eq 0 ]; then
    log "Camera test successful"
    check_image_quality
    
    # Clean up
    if [ -f "camera_test.jpg" ]; then
        info "Test image available at: $(pwd)/camera_test.jpg"
    fi
else
    error "Camera test failed"
    exit 1
fi

# Print summary
echo ""
echo -e "${GREEN}=== TEST SUMMARY ===${NC}"
if [ $camera_result -eq 0 ]; then
    echo -e "Camera Status: ${GREEN}Working${NC}"
else
    echo -e "Camera Status: ${RED}Failed${NC}"
fi

echo ""
echo -e "${BLUE}Recommendations:${NC}"
echo "1. If image is too dark/bright, adjust lighting conditions"
echo "2. If image is blurry, clean the camera lens"
echo "3. For best face recognition, ensure good lighting and clear view of faces"
echo "4. Minimum recommended resolution is 640x480"
echo ""
echo -e "${YELLOW}Note: You can view the test image at: $(pwd)/camera_test.jpg${NC}" 