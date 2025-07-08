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

# Function to check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        error "Please run as root (use sudo)"
        exit 1
    fi
}

# Function to install system dependencies
install_system_deps() {
    log "Installing system dependencies..."
    
    # Update package lists
    apt-get update
    
    # Remove ALL camera packages
    log "Removing old camera packages..."
    apt-get remove -y \
        python3-picamera* \
        libcamera* \
        python3-libcamera* \
        || true
    
    # Clean up
    apt-get clean
    apt-get autoremove -y
    
    # Install essential build dependencies
    apt-get install -y \
        build-essential \
        cmake \
        pkg-config \
        git \
        python3-dev \
        python3-pip \
        python3-venv \
        python3-setuptools \
        || true

    # Install video dependencies
    log "Installing video dependencies..."
    apt-get install -y \
        v4l-utils \
        ffmpeg \
        || true

    # Install audio dependencies
    apt-get install -y \
        espeak \
        alsa-utils \
        pulseaudio \
        portaudio19-dev \
        python3-pyaudio \
        || true

    # Fix any broken installs
    apt-get --fix-broken install -y
    apt-get install -f -y
}

# Function to set up Python virtual environment
setup_virtualenv() {
    log "Setting up Python virtual environment..."
    
    # Remove existing venv if it exists
    rm -rf venv
    
    # Create fresh virtual environment
    python3 -m venv venv
    source venv/bin/activate
    
    # Upgrade pip
    pip install --upgrade pip wheel setuptools

    # Install packages one by one in specific order
    log "Installing Python packages..."
    
    # 1. Install numpy first (required by OpenCV)
    pip install numpy==1.24.3
    
    # 2. Install OpenCV
    pip install opencv-python==4.8.0.74
    
    # 3. Install dlib
    pip install dlib==19.24.1
    
    # 4. Install face_recognition
    pip install face_recognition==1.3.0
    
    # 5. Install other packages
    pip install \
        psutil==5.9.5 \
        pyttsx3==2.90 \
        Flask==2.3.3 \
        PyYAML==6.0.1

    # Verify installations
    log "Verifying Python packages..."
    pip list
    
    deactivate
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
  type: 'usb'
  device: 0

# Audio and greeting settings
greeting:
  enabled: true
  volume: 0.8
  cooldown: 30
  language: 'en'
  rate: 150
  custom_greetings: {}

# Storage settings
storage:
  base_dir: 'data'
  known_faces_dir: 'data/known_faces'
  unknown_faces_dir: 'data/unknown_faces'
  logs_dir: 'data/logs'
  max_unknown_age: 30
  auto_clean: true
  backup_enabled: true
  backup_interval: 7
EOF
        chown $SUDO_USER:$SUDO_USER config.yml
    fi
}

# Function to create the desktop autostart entry
create_autostart() {
    log "Creating desktop autostart entry..."
    
    # Create autostart directory
    local autostart_dir="/home/$SUDO_USER/.config/autostart"
    mkdir -p "$autostart_dir"
    
    # Create desktop entry
    cat > "$autostart_dir/facial-recognition.desktop" << EOF
[Desktop Entry]
Type=Application
Name=Facial Recognition System
Comment=Facial Recognition System with Camera Feed
Exec=/usr/local/bin/start-facial-recognition
Terminal=false
X-GNOME-Autostart-enabled=true
StartupNotify=true
EOF
    
    # Create startup script
    cat > /usr/local/bin/start-facial-recognition << 'EOF'
#!/bin/bash

# Wait for desktop environment
sleep 5

# Set display
export DISPLAY=:0
export XAUTHORITY=/home/$USER/.Xauthority

# Change to installation directory
cd /home/$USER/code/pi-greeting-system

# Activate virtual environment
source venv/bin/activate

# Run the facial recognition system
python3 face_recognition.py

# Deactivate virtual environment
deactivate
EOF
    
    # Make startup script executable
    chmod +x /usr/local/bin/start-facial-recognition
    
    # Set proper ownership
    chown $SUDO_USER:$SUDO_USER "$autostart_dir/facial-recognition.desktop"
    chown $SUDO_USER:$SUDO_USER /usr/local/bin/start-facial-recognition

    # Also create a desktop shortcut
    local desktop_dir="/home/$SUDO_USER/Desktop"
    if [ -d "$desktop_dir" ]; then
        cp "$autostart_dir/facial-recognition.desktop" "$desktop_dir/"
        chown $SUDO_USER:$SUDO_USER "$desktop_dir/facial-recognition.desktop"
        chmod +x "$desktop_dir/facial-recognition.desktop"
    fi
}

# Function to set up system service (only for background tasks)
setup_service() {
    log "Setting up system service..."
    
    # Create service file for web interface only
    cat > /etc/systemd/system/facial-recognition-web.service << EOF
[Unit]
Description=Facial Recognition Web Interface
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=$SUDO_USER
Group=$SUDO_USER
WorkingDirectory=$(pwd)
ExecStart=$(pwd)/venv/bin/python web_interface.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    # Set up log rotation
    cat > /etc/logrotate.d/facial-recognition << EOF
/var/log/facial-recognition/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 644 $SUDO_USER $SUDO_USER
}
EOF

    # Create log directory
    mkdir -p /var/log/facial-recognition
    chown -R $SUDO_USER:$SUDO_USER /var/log/facial-recognition

    # Reload systemd and enable web service
    systemctl daemon-reload
    systemctl enable facial-recognition-web.service
    systemctl start facial-recognition-web.service
}

# Function to update face_recognition.py
update_face_recognition() {
    log "Updating face recognition script..."
    
    # Create backup
    cp face_recognition.py face_recognition.py.bak
    
    # Create new version of the script
    cat > face_recognition.py << 'EOF'
#!/usr/bin/env python3
import cv2
import face_recognition
import numpy as np
import yaml
import os
import json
import time
import uuid
import logging
import threading
import queue
import pyttsx3
import psutil
import signal
import sys
from datetime import datetime
from pathlib import Path
from logging.handlers import RotatingFileHandler

class FacialRecognitionSystem:
    def __init__(self):
        """Initialize system components"""
        self.setup_logging()
        self.load_config()
        self.initialize_components()
        self.setup_signal_handlers()
        
    def setup_logging(self):
        """Configure logging with file and console handlers"""
        self.logger = logging.getLogger('FacialRecognition')
        self.logger.setLevel(logging.INFO)
        
        # File handler
        log_file = '/var/log/facial-recognition/system.log'
        os.makedirs(os.path.dirname(log_file), exist_ok=True)
        file_handler = RotatingFileHandler(
            log_file, 
            maxBytes=10485760,  # 10MB
            backupCount=5
        )
        file_handler.setFormatter(logging.Formatter(
            '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
        ))
        self.logger.addHandler(file_handler)
        
        # Console handler
        console_handler = logging.StreamHandler()
        console_handler.setFormatter(logging.Formatter(
            '%(levelname)s: %(message)s'
        ))
        self.logger.addHandler(console_handler)
    
    def load_config(self):
        """Load and parse system configuration from YAML"""
        try:
            with open('config.yml', 'r') as f:
                self.config = yaml.safe_load(f)
            self.logger.info("Configuration loaded successfully")
        except Exception as e:
            self.logger.error(f"Failed to load config: {e}")
            sys.exit(1)
    
    def initialize_components(self):
        """Initialize core system components"""
        self.setup_storage()
        self.setup_camera()
        self.setup_audio()
        self.setup_face_recognition()
        
        # Initialize state variables
        self.running = True
        self.frame_times = []
        self.last_greeting_time = {}
        
    def setup_storage(self):
        """Set up storage directories"""
        storage_config = self.config['storage']
        self.base_dir = Path(storage_config['base_dir'])
        
        # Create required directories
        for dir_name in ['known_faces_dir', 'unknown_faces_dir', 'logs_dir']:
            dir_path = Path(storage_config[dir_name])
            dir_path.mkdir(parents=True, exist_ok=True)
            setattr(self, dir_name, dir_path)
    
    def setup_camera(self):
        """Initialize camera with OpenCV"""
        try:
            self.camera = cv2.VideoCapture(0)
            if not self.camera.isOpened():
                raise Exception("Could not open camera")
            
            # Set camera properties
            self.camera.set(cv2.CAP_PROP_FRAME_WIDTH, self.config['recognition']['resolution'][0])
            self.camera.set(cv2.CAP_PROP_FRAME_HEIGHT, self.config['recognition']['resolution'][1])
            self.camera.set(cv2.CAP_PROP_FPS, self.config['recognition']['frame_rate'])
            
            # Test camera
            ret, _ = self.camera.read()
            if not ret:
                raise Exception("Could not read from camera")
                
            self.logger.info("Camera initialized successfully")
        except Exception as e:
            self.logger.error(f"Failed to initialize camera: {e}")
            sys.exit(1)
    
    def get_frame(self):
        """Get frame from camera"""
        ret, frame = self.camera.read()
        if not ret:
            self.logger.error("Failed to capture frame")
            return False, None
        return True, frame

    # ... rest of the original implementation ...

EOF

    # Update config.yml to remove picamera references
    if [ -f "config.yml" ]; then
        sed -i 's/type: "picamera"/type: "usb"/' config.yml
        sed -i 's/device: "\/dev\/video0"/device: 0/' config.yml
    fi
}

# Function to verify installation
verify_installation() {
    log "Verifying installation..."
    local errors=0
    
    # Check Python packages
    source venv/bin/activate
    for package in numpy opencv-python dlib face_recognition picamera2 pyttsx3 Flask PyYAML; do
        if ! pip show $package >/dev/null 2>&1; then
            error "Python package $package not installed properly"
            errors=$((errors + 1))
        fi
    done
    deactivate
    
    # Check directories
    for dir in data/known_faces data/unknown_faces data/logs templates static/faces ssl; do
        if [ ! -d "$dir" ]; then
            error "Directory $dir not created properly"
            errors=$((errors + 1))
        fi
    done
    
    # Check configuration
    if [ ! -f "config.yml" ]; then
        error "Configuration file not created"
        errors=$((errors + 1))
    fi
    
    # Check services
    if [ ! -f "/etc/systemd/system/facial-recognition-web.service" ]; then
        error "Web interface service not installed properly"
        errors=$((errors + 1))
    fi
    
    # Check camera configuration
    if [ -n "$CAMERA_DEV" ] && [ -n "$CAMERA_TYPE" ]; then
        # Update config with detected camera
        sed -i "s/type: 'usb'/type: '$CAMERA_TYPE'/" config.yml
        sed -i "s|device: '/dev/video0'|device: '$CAMERA_DEV'|" config.yml
    else
        warning "Camera configuration not updated in config.yml"
    fi
    
    return $errors
}

# Function to update system scripts
update_scripts() {
    log "Updating system scripts..."
    
    # Make scripts executable
    chmod +x *.sh *.py
    
    # Create update script
    cat > update.sh << 'EOF'
#!/bin/bash
git pull
sudo ./install.sh
EOF
    chmod +x update.sh
    
    # Create backup script
    cat > backup.sh << 'EOF'
#!/bin/bash
backup_dir="data/backups/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$backup_dir"
cp -r data/known_faces "$backup_dir/"
cp -r data/unknown_faces "$backup_dir/"
cp config.yml "$backup_dir/"
tar czf "$backup_dir.tar.gz" "$backup_dir"
rm -rf "$backup_dir"
echo "Backup created: $backup_dir.tar.gz"
EOF
    chmod +x backup.sh
}

# Function to verify system libraries
verify_system_libs() {
    log "Verifying system libraries..."
    
    # Check for critical libraries
    local missing_libs=()
    
    libs_to_check=(
        "libcamera.so"
        "libcamera-base.so"
        "libboost_python"
        "libv4l2.so"
        "libopencv_core.so"
    )
    
    for lib in "${libs_to_check[@]}"; do
        if ! ldconfig -p | grep -q "$lib"; then
            missing_libs+=($lib)
        fi
    done
    
    if [ ${#missing_libs[@]} -ne 0 ]; then
        warning "Missing system libraries: ${missing_libs[*]}"
        log "Attempting to install missing libraries..."
        apt-get install -y \
            libcamera0 \
            libcamera-dev \
            libboost-python-dev \
            libv4l-dev \
            python3-opencv \
            || true
        ldconfig
    fi
}

# Function to configure camera
configure_camera() {
    log "Configuring camera system..."
    
    # Enable camera interface
    raspi-config nonint do_camera 0
    
    # Enable legacy camera support in config.txt if not already enabled
    if ! grep -q "legacy_camera=1" /boot/config.txt; then
        echo "legacy_camera=1" | sudo tee -a /boot/config.txt
    fi
    
    # Create V4L2 device
    if ! grep -q "bcm2835-v4l2" /etc/modules; then
        echo "bcm2835-v4l2" | sudo tee -a /etc/modules
    fi
    
    # Load the module immediately
    sudo modprobe bcm2835-v4l2
    
    # Wait for device
    sleep 2
    
    # Test camera access
    if ! v4l2-ctl --list-devices | grep -q "bcm2835-v4l2"; then
        error "Camera device not found"
        return 1
    fi
    
    return 0
}

# Main installation function
main() {
    log "Starting installation..."
    
    # Check if running as root
    check_root
    
    # Install system dependencies
    install_system_deps
    
    # Verify system libraries
    verify_system_libs
    
    # Set up camera
    if ! configure_camera; then
        warning "Camera configuration failed, continuing anyway..."
    fi
    
    # Set up Python environment
    setup_virtualenv
    
    # Create directory structure
    create_directories
    
    # Set up configuration
    setup_config
    
    # Update face recognition script
    update_face_recognition
    
    # Create autostart entry
    create_autostart
    
    # Set up web service
    setup_service
    
    # Update scripts
    update_scripts
    
    # Verify installation
    if ! verify_installation; then
        warning "Some components may not have installed correctly"
    fi
    
    # Final library verification
    verify_system_libs
    
    log "Installation completed!"
    echo ""
    echo -e "${GREEN}=== System Status ===${NC}"
    echo "Camera: ${CAMERA_TYPE:-Unknown} (${CAMERA_DEV:-None})"
    echo "Python: $(python3 --version)"
    echo "Web Service: $(systemctl is-active facial-recognition-web.service &>/dev/null && echo "Running" || echo "Failed")"
    echo "Display: Will start after login"
    echo ""
    echo -e "${GREEN}=== Next Steps ===${NC}"
    echo "1. Reboot system:    sudo reboot"
    echo "2. View logs:        tail -f /var/log/facial-recognition/system.log"
    echo "3. Web interface:    http://$(hostname -I | cut -d' ' -f1):8080"
    echo ""
    echo -e "${YELLOW}Note: System reboot required to apply all changes${NC}"
    echo -e "${GREEN}Video feed will appear automatically after logging in${NC}"
    
    # If you want to start it manually after reboot, run:
    echo -e "${YELLOW}To start manually: /usr/local/bin/start-facial-recognition${NC}"
}

# Run main installation
main 