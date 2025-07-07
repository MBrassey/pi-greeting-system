#!/bin/bash

# Raspberry Pi Facial Recognition System Installer
# This script handles the complete installation and setup of the system

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

# Check if script is run as root
if [[ $EUID -eq 0 ]]; then
   error "This script should not be run as root. Please run as a regular user."
   exit 1
fi

# Check if running on Raspberry Pi
if ! grep -q "Raspberry Pi" /proc/cpuinfo; then
    warning "This system may not be a Raspberry Pi. Some features might not work as expected."
fi

# Check for Python 3.7+
if ! command -v python3 &> /dev/null; then
    error "Python 3 is not installed. Please install Python 3.7 or newer."
    exit 1
fi

PYTHON_VERSION=$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')
if (( $(echo "$PYTHON_VERSION < 3.7" | bc -l) )); then
    error "Python 3.7 or newer is required. Found version $PYTHON_VERSION"
    exit 1
fi

# Run system compatibility check
log "Running system compatibility check..."
if ! ./check_system.sh; then
    error "System compatibility check failed. Please fix the issues and try again."
    exit 1
fi

# Create project structure
log "Creating project structure..."
mkdir -p data/{known_faces,unknown_faces,logs,backups}
mkdir -p ssl
mkdir -p config

# Check and install system dependencies
log "Checking and installing system dependencies..."
DEPS=(
    "python3-pip"
    "python3-dev"
    "python3-venv"
    "build-essential"
    "cmake"
    "pkg-config"
    "libjpeg-dev"
    "libtiff5-dev"
    "libjasper-dev"
    "libpng-dev"
    "libavcodec-dev"
    "libavformat-dev"
    "libswscale-dev"
    "libv4l-dev"
    "libxvidcore-dev"
    "libx264-dev"
    "libgtk-3-dev"
    "libcanberra-gtk*"
    "libatlas-base-dev"
    "gfortran"
    "espeak"
    "espeak-data"
    "alsa-utils"
    "pulseaudio"
    "git"
)

# Update package list
log "Updating package list..."
sudo apt update

# Install dependencies
log "Installing system dependencies..."
for dep in "${DEPS[@]}"; do
    if ! dpkg -l | grep -q "^ii  $dep"; then
        info "Installing $dep..."
        sudo apt install -y "$dep"
    else
        info "$dep is already installed"
    fi
done

# Create and activate virtual environment
log "Setting up Python virtual environment..."
if [ ! -d "venv" ]; then
    python3 -m venv venv
fi
source venv/bin/activate

# Upgrade pip
log "Upgrading pip..."
python3 -m pip install --upgrade pip

# Install Python packages
log "Installing Python packages (this may take a while)..."
pip install -r requirements.txt

# Configure camera
log "Configuring camera..."
if ! ls /dev/video* &> /dev/null; then
    warning "No video devices found. Please check camera connection."
    warning "If using Pi Camera, make sure it's enabled in raspi-config"
fi

# Test camera access
if [ -e /dev/video0 ]; then
    log "Testing camera access..."
    if ! python3 -c "import cv2; cap = cv2.VideoCapture(0); ret, frame = cap.read(); cap.release(); assert ret" 2>/dev/null; then
        warning "Camera test failed. Please check permissions and connections."
    else
        info "Camera test successful"
    fi
fi

# Configure audio
log "Configuring audio..."
if ! command -v espeak &> /dev/null; then
    warning "espeak not found. Voice greetings may not work."
else
    log "Testing audio system..."
    if ! espeak "Audio system test" 2>/dev/null; then
        warning "Audio test failed. Please check speaker connection and volume."
    else
        info "Audio test successful"
    fi
fi

# Set up systemd service
log "Setting up systemd service..."
sudo tee /etc/systemd/system/facial-recognition.service > /dev/null << EOF
[Unit]
Description=Facial Recognition System
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$PWD
Environment=PATH=$PWD/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=$PWD/venv/bin/python face_recognition.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Set up log rotation
log "Setting up log rotation..."
sudo tee /etc/logrotate.d/facial-recognition > /dev/null << EOF
/var/log/facial-recognition/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 640 $USER $USER
}
EOF

# Create log directory
sudo mkdir -p /var/log/facial-recognition
sudo chown -R $USER:$USER /var/log/facial-recognition

# Make scripts executable
log "Setting permissions..."
chmod +x *.sh
chmod +x *.py

# Generate initial configuration
if [ ! -f "config.yml" ]; then
    log "Generating initial configuration..."
    cp config.yml.example config.yml
fi

# Create SSL certificate for web interface
if [ ! -f "ssl/cert.pem" ] && [ ! -f "ssl/key.pem" ]; then
    log "Generating SSL certificate for web interface..."
    mkdir -p ssl
    openssl req -x509 -newkey rsa:4096 -nodes -out ssl/cert.pem -keyout ssl/key.pem -days 365 \
        -subj "/C=US/ST=State/L=City/O=Organization/OU=Unit/CN=localhost"
fi

# Final setup
log "Running final setup..."
python3 setup.py

# Installation complete
log "Installation complete!"
echo ""
echo -e "${GREEN}=== INSTALLATION SUMMARY ===${NC}"
echo -e "Project directory: ${BLUE}$PWD${NC}"
echo -e "Virtual environment: ${BLUE}$PWD/venv${NC}"
echo -e "Configuration: ${BLUE}$PWD/config.yml${NC}"
echo -e "Log directory: ${BLUE}/var/log/facial-recognition${NC}"
echo ""
echo -e "${GREEN}=== NEXT STEPS ===${NC}"
echo "1. Review and edit config.yml for your setup"
echo "2. Add known faces using add_face.sh"
echo "3. Start the system:"
echo "   - Development: ./start.sh"
echo "   - Production: sudo systemctl start facial-recognition"
echo ""
echo -e "${YELLOW}Note: For first-time setup, it's recommended to run in development mode first.${NC}"
echo "See README.md for detailed usage instructions."

# Cleanup
deactivate 