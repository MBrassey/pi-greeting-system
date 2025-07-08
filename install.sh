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
    
    # Install essential build dependencies first
    apt-get install -y \
        build-essential \
        cmake \
        pkg-config \
        libcap-dev \
        libx11-dev \
        libatlas-base-dev \
        libgtk-3-dev \
        libboost-python-dev \
        || true

    # Install camera and video dependencies
    apt-get install -y \
        v4l-utils \
        i2c-tools \
        libavcodec-dev \
        libavformat-dev \
        libswscale-dev \
        libv4l-dev \
        libxvidcore-dev \
        libx264-dev \
        libgtk-3-dev \
        || true

    # Install Python dependencies
    apt-get install -y \
        python3-dev \
        python3-pip \
        python3-venv \
        python3-wheel \
        python3-setuptools \
        python3-opencv \
        python3-picamera2 \
        python3-numpy \
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
}

# Function to set up Python virtual environment
setup_virtualenv() {
    log "Setting up Python virtual environment..."
    
    # Create virtual environment if it doesn't exist
    if [ ! -d "venv" ]; then
        python3 -m venv venv
    fi
    
    # Activate virtual environment
    source venv/bin/activate
    
    # Upgrade pip
    pip install --upgrade pip wheel setuptools

    # Install numpy first (required for other packages)
    pip install numpy

    # Install dlib with custom flags
    pip install dlib --no-cache-dir --install-option="--no" --install-option="--dlib" --install-option="USE_AVX_INSTRUCTIONS"

    # Install other packages one by one with retries
    packages=(
        "opencv-python"
        "face_recognition"
        "picamera2"
        "pyttsx3"
        "Flask"
        "PyYAML"
    )

    for package in "${packages[@]}"; do
        log "Installing $package..."
        pip install --no-cache-dir $package || {
            warning "First attempt to install $package failed, retrying..."
            pip install --no-cache-dir --ignore-installed $package
        }
    done
    
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
# Raspberry Pi Facial Recognition System Configuration

# Recognition settings
recognition:
  tolerance: 0.6
  model: 'hog'
  frame_rate: 30
  resolution: [1280, 720]
  min_face_size: 20
  blur_threshold: 100

# Camera settings
camera:
  type: 'usb'  # Will be updated by install script
  device: '/dev/video0'  # Will be updated by install script
  brightness: 50
  contrast: 50

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

# Web interface settings
web_interface:
  enabled: true
  host: '0.0.0.0'
  port: 8080
  ssl_enabled: false
  ssl_cert: 'ssl/cert.pem'
  ssl_key: 'ssl/key.pem'
  username: 'admin'
  password_hash: ''  # Will be set on first run

# Security settings
security:
  encrypt_faces: false
  encryption_key: ''  # Will be set on first run
  allowed_ips: []
  session_timeout: 3600
  max_login_attempts: 5
  lockout_duration: 300

# Performance settings
performance:
  max_processes: 4
  batch_size: 32
  gpu_enabled: false
  optimize_for: 'balanced'
EOF
        chown $SUDO_USER:$SUDO_USER config.yml
        chmod 644 config.yml
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
EOF
    
    # Create startup script in /usr/local/bin
    cat > /usr/local/bin/start-facial-recognition << 'EOF'
#!/bin/bash

# Wait for desktop environment to be fully loaded
sleep 10

# Set display
export DISPLAY=:0
export XAUTHORITY=/home/$USER/.Xauthority

# Change to installation directory
cd /home/$USER/code/pi-greeting-system

# Activate virtual environment and run
source venv/bin/activate
python3 face_recognition.py --display

# Deactivate virtual environment
deactivate
EOF
    
    # Make startup script executable
    chmod +x /usr/local/bin/start-facial-recognition
    
    # Set proper ownership
    chown $SUDO_USER:$SUDO_USER "$autostart_dir/facial-recognition.desktop"
    chown $SUDO_USER:$SUDO_USER /usr/local/bin/start-facial-recognition
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
    
    # Add display argument handling to face_recognition.py
    if ! grep -q "add_argument('--display'" "face_recognition.py"; then
        # Create backup
        cp face_recognition.py face_recognition.py.bak
        
        # Add argument parsing if not present
        if ! grep -q "ArgumentParser" "face_recognition.py"; then
            sed -i '1i import argparse' face_recognition.py
            sed -i '/if __name__ == "__main__":/a\    parser = argparse.ArgumentParser()\n    parser.add_argument("--display", action="store_true", help="Show video window")\n    args = parser.parse_args()' face_recognition.py
        fi
        
        # Update the window display code
        sed -i 's/cv2.imshow("Facial Recognition System", frame)/if args.display:\n            cv2.imshow("Facial Recognition System", frame)\n            cv2.moveWindow("Facial Recognition System", 0, 0)/' face_recognition.py
        
        # Ensure window stays on top
        if ! grep -q "cv2.WINDOW_GUI_NORMAL" "face_recognition.py"; then
            sed -i '/class FacialRecognitionSystem:/a\    def setup_display(self):\n        if args.display:\n            cv2.namedWindow("Facial Recognition System", cv2.WINDOW_GUI_NORMAL)\n            cv2.setWindowProperty("Facial Recognition System", cv2.WND_PROP_FULLSCREEN, cv2.WINDOW_FULLSCREEN)' face_recognition.py
            sed -i '/def __init__(self):/a\        self.setup_display()' face_recognition.py
        fi
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

# Main installation function
main() {
    log "Starting installation..."
    
    # Check if running as root
    check_root
    
    # Install system dependencies
    install_system_deps
    
    # Set up camera
    if ! detect_camera_type; then
        warning "No camera detected, continuing anyway..."
    fi
    
    if [ -n "$CAMERA_TYPE" ]; then
        if ! configure_camera; then
            warning "Camera configuration failed, continuing anyway..."
        fi
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