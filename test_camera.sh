#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Function to print error messages
error() {
    echo -e "${RED}ERROR: $1${NC}" >&2
}

# Function to print info messages
info() {
    echo -e "${BLUE}INFO: $1${NC}"
}

echo -e "${BLUE}=== Raspberry Pi Camera Test ===${NC}"
echo "Testing Arducam IMX519 16MP Camera Module..."

# Check if picamera2 is installed
if ! python3 -c "import picamera2" 2>/dev/null; then
    error "picamera2 module not found"
    error "Please run install.sh first"
    exit 1
fi

# Test camera detection
echo -e "\nChecking camera connection..."
if ! libcamera-hello --list-cameras 2>/dev/null | grep -q "imx519\|Available cameras"; then
    error "IMX519 camera not detected"
    error "Please check camera connection and ribbon cable"
    exit 1
else
    info "Camera detected successfully"
fi

# Create test script
echo "Creating camera test script..."
cat > test_camera.py << 'EOF'
from picamera2 import Picamera2
import time

def test_camera():
    try:
        # Initialize camera
        picam2 = Picamera2()
        
        # Configure camera for full resolution capture
        config = picam2.create_still_configuration(
            main={"size": (4656, 3496)},  # Full 16MP resolution
            lores={"size": (1920, 1080)},  # Preview resolution
            display="lores"
        )
        picam2.configure(config)
        
        # Start camera
        picam2.start()
        time.sleep(2)  # Warm-up time
        
        # Capture test image
        picam2.capture_file("camera_test_full.jpg")
        
        # Switch to video configuration
        video_config = picam2.create_video_configuration(
            main={"size": (1920, 1080)},
            controls={"FrameDurationLimits": (33333, 33333)}  # 30fps
        )
        picam2.configure(video_config)
        picam2.start()
        time.sleep(1)
        
        # Capture test frame
        picam2.capture_file("camera_test_video.jpg")
        
        picam2.close()
        return True
    except Exception as e:
        print(f"Error: {e}")
        return False

if __name__ == "__main__":
    success = test_camera()
    exit(0 if success else 1)
EOF

# Run test script
echo -e "\nTesting camera functionality..."
if python3 test_camera.py; then
    info "Camera test completed successfully"
    camera_result=0
else
    error "Camera test failed"
    camera_result=1
fi

# Print summary
echo ""
echo -e "${GREEN}=== TEST SUMMARY ===${NC}"
if [ $camera_result -eq 0 ]; then
    echo -e "Camera Status: ${GREEN}Working${NC}"
    echo -e "\nTest images captured:"
    echo "1. Full resolution (16MP): camera_test_full.jpg"
    echo "2. Video resolution (1080p): camera_test_video.jpg"
else
    echo -e "Camera Status: ${RED}Failed${NC}"
fi

echo ""
echo -e "${BLUE}Recommendations:${NC}"
echo "1. If image is too dark/bright, adjust lighting conditions"
echo "2. If image is blurry, clean the camera lens"
echo "3. For best face recognition, ensure good lighting and clear view of faces"
echo "4. The IMX519 performs best with good lighting due to its high resolution"
echo "5. Consider using a tripod or stable mount for the camera"
echo ""
echo -e "${YELLOW}Note: You can view the test images at:${NC}"
echo "- Full resolution: $(pwd)/camera_test_full.jpg"
echo -e "- Video resolution: $(pwd)/camera_test_video.jpg"

# Cleanup
rm -f test_camera.py

exit $camera_result