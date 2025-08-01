#!/bin/bash

# Service Installation Script for Raspberry Pi Facial Recognition System
# Sets up systemd service for automatic startup after X11 loads

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
if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root"
   info "Please run: sudo $0"
   exit 1
fi

# Get the actual user who ran sudo
ACTUAL_USER=${SUDO_USER:-$USER}
if [ "$ACTUAL_USER" = "root" ]; then
    error "Please run this script with sudo, not as root directly"
    exit 1
fi

# Get user's home directory
USER_HOME=$(getent passwd "$ACTUAL_USER" | cut -d: -f6)

# Get absolute path to project directory
PROJECT_DIR=$(pwd)

# Verify project files exist
required_files=("facial_recognition_system.py" "web_interface.py" "config.yml")
for file in "${required_files[@]}"; do
    if [ ! -f "$PROJECT_DIR/$file" ]; then
        error "Required file $file not found in $PROJECT_DIR"
        exit 1
    fi
done

# Verify virtual environment exists
if [ ! -d "$PROJECT_DIR/venv" ]; then
    error "Virtual environment not found. Please run install.sh first."
    exit 1
fi

# Add user to required groups for hardware access
log "Adding user to required groups..."
usermod -a -G video,audio,gpio,i2c $ACTUAL_USER

# Create systemd service file for face recognition
log "Creating face recognition service..."
cat > /etc/systemd/system/facial-recognition.service << EOF
[Unit]
Description=Facial Recognition System
After=graphical.target
Wants=graphical.target
Requires=dev-video0.device
ConditionPathExists=/dev/video0

[Service]
Type=simple
User=$ACTUAL_USER
Group=$ACTUAL_USER
WorkingDirectory=$PROJECT_DIR
Environment=PATH=$PROJECT_DIR/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
Environment=HOME=$USER_HOME
Environment=USER=$ACTUAL_USER
Environment=DISPLAY=:0
Environment=XAUTHORITY=$USER_HOME/.Xauthority

# Wait for X11 to be ready
ExecStartPre=/bin/bash -c 'while ! pgrep -x "Xorg" > /dev/null; do sleep 1; done'
ExecStartPre=/bin/sleep 3

# Start the facial recognition system
ExecStart=$PROJECT_DIR/venv/bin/python facial_recognition_system.py

Restart=always
RestartSec=10
StandardOutput=append:/var/log/facial-recognition/system.log
StandardError=append:/var/log/facial-recognition/system.log

[Install]
WantedBy=graphical.target
EOF

# Create systemd service file for web interface
log "Creating web interface service..."
cat > /etc/systemd/system/facial-recognition-web.service << EOF
[Unit]
Description=Facial Recognition Web Interface
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=$ACTUAL_USER
Group=$ACTUAL_USER
WorkingDirectory=$PROJECT_DIR
Environment=PATH=$PROJECT_DIR/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
Environment=HOME=$USER_HOME
Environment=USER=$ACTUAL_USER

ExecStart=$PROJECT_DIR/venv/bin/python web_interface.py

Restart=always
RestartSec=10
StandardOutput=append:/var/log/facial-recognition/web.log
StandardError=append:/var/log/facial-recognition/web.log

[Install]
WantedBy=multi-user.target
EOF

# Create log directory
log "Setting up log directory..."
mkdir -p /var/log/facial-recognition
chown -R $ACTUAL_USER:$ACTUAL_USER /var/log/facial-recognition

# Set up log rotation
log "Setting up log rotation..."
cat > /etc/logrotate.d/facial-recognition << EOF
/var/log/facial-recognition/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 640 $ACTUAL_USER $ACTUAL_USER
    sharedscripts
    postrotate
        systemctl restart facial-recognition facial-recognition-web
    endscript
}
EOF

# Set up udev rules for camera access
log "Setting up camera permissions..."
cat > /etc/udev/rules.d/99-facial-recognition.rules << EOF
SUBSYSTEM=="video4linux", GROUP="video", MODE="0660"
SUBSYSTEM=="vchiq", GROUP="video", MODE="0660"
SUBSYSTEM=="i2c-dev", GROUP="i2c", MODE="0660"
EOF

# Reload systemd configuration
log "Reloading systemd configuration..."
systemctl daemon-reload
udevadm control --reload-rules

# Enable services
log "Enabling services..."
systemctl enable facial-recognition.service
systemctl enable facial-recognition-web.service

# Create convenience scripts
log "Creating convenience scripts..."

# Start script
cat > "$PROJECT_DIR/service_start.sh" << EOF
#!/bin/bash
sudo systemctl start facial-recognition facial-recognition-web
sudo systemctl status facial-recognition facial-recognition-web --no-pager
EOF

# Stop script
cat > "$PROJECT_DIR/service_stop.sh" << EOF
#!/bin/bash
sudo systemctl stop facial-recognition facial-recognition-web
sudo systemctl status facial-recognition facial-recognition-web --no-pager
EOF

# Restart script
cat > "$PROJECT_DIR/service_restart.sh" << EOF
#!/bin/bash
sudo systemctl restart facial-recognition facial-recognition-web
sudo systemctl status facial-recognition facial-recognition-web --no-pager
EOF

# Status script
cat > "$PROJECT_DIR/service_status.sh" << EOF
#!/bin/bash
echo "=== Facial Recognition System Status ==="
sudo systemctl status facial-recognition --no-pager
echo
echo "=== Web Interface Status ==="
sudo systemctl status facial-recognition-web --no-pager
EOF

# Make scripts executable
chmod +x "$PROJECT_DIR/service_"*.sh
chown $ACTUAL_USER:$ACTUAL_USER "$PROJECT_DIR/service_"*.sh

# Create uninstall script
log "Creating uninstall script..."
cat > "$PROJECT_DIR/uninstall_service.sh" << EOF
#!/bin/bash
# Uninstall Facial Recognition System Services

if [[ \$EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

echo "Stopping services..."
systemctl stop facial-recognition facial-recognition-web

echo "Disabling services..."
systemctl disable facial-recognition facial-recognition-web

echo "Removing service files..."
rm -f /etc/systemd/system/facial-recognition.service
rm -f /etc/systemd/system/facial-recognition-web.service

echo "Removing log rotation configuration..."
rm -f /etc/logrotate.d/facial-recognition

echo "Removing udev rules..."
rm -f /etc/udev/rules.d/99-facial-recognition.rules

echo "Reloading systemd configuration..."
systemctl daemon-reload

echo "Service uninstallation complete"
EOF

chmod +x "$PROJECT_DIR/uninstall_service.sh"
chown $ACTUAL_USER:$ACTUAL_USER "$PROJECT_DIR/uninstall_service.sh"

# Start services for testing
log "Starting services for testing..."
systemctl start facial-recognition.service
systemctl start facial-recognition-web.service

# Check service status
sleep 3
facial_status=$(systemctl is-active facial-recognition)
web_status=$(systemctl is-active facial-recognition-web)

# Print status and instructions
echo ""
echo -e "${GREEN}=== INSTALLATION SUMMARY ===${NC}"
echo -e "Face Recognition Service: ${BLUE}$facial_status${NC}"
echo -e "Web Interface Service: ${BLUE}$web_status${NC}"
echo -e "Log Directory: ${BLUE}/var/log/facial-recognition${NC}"
echo ""
echo -e "${GREEN}=== MANAGEMENT COMMANDS ===${NC}"
echo -e "Start services:   ${BLUE}./service_start.sh${NC}"
echo -e "Stop services:    ${BLUE}./service_stop.sh${NC}"
echo -e "Restart services: ${BLUE}./service_restart.sh${NC}"
echo -e "Check status:     ${BLUE}./service_status.sh${NC}"
echo ""
echo -e "${GREEN}=== NEXT STEPS ===${NC}"
echo "1. Reboot system: sudo reboot"
echo "2. System will automatically start facial recognition after boot"
echo "3. Check web interface: http://$(hostname -I | awk '{print $1}'):8080"
echo "4. View logs: tail -f /var/log/facial-recognition/system.log"
echo ""
echo -e "${GREEN}Installation complete!${NC}"
echo -e "${YELLOW}Reboot to activate automatic startup:${NC} ${BLUE}sudo reboot${NC}" 