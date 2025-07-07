# Raspberry Pi Facial Recognition & Greeting System

Real-time facial recognition system with voice greetings for Raspberry Pi. The system performs automatic face detection, recognition of known individuals, voice greeting synthesis, and unknown visitor logging.

## Quick Start

1. **Installation**
```bash
# Clone repository
git clone https://github.com/mbrassey/pi-greeting-system
cd pi-greeting-system

# Run installation
./install.sh
```

2. **Face Registration**
```bash
# From image file
./add_face.sh /path/to/photo.jpg "John Doe"

# Via camera capture
./add_face.sh --capture "John Doe"
```

3. **System Launch**
```bash
# Development mode (with display)
./start.sh

# Service mode (background)
sudo ./install_service.sh
```

## Hardware Requirements

- **Minimum Specifications**:
  - Raspberry Pi 3B+ or newer (Pi 4 recommended)
  - 2GB RAM (4GB+ recommended)
  - 16GB SD card with 5GB+ free space
  - USB webcam or Pi Camera Module
  - Audio output device for voice synthesis

- **Recommended Configuration**:
  - Raspberry Pi 4 (4GB or 8GB RAM)
  - Pi Camera Module v2/v3
  - Official Raspberry Pi 7" Display
  - USB/Bluetooth Speaker
  - 32GB+ SD Card

## Installation Guide

### 1. System Preparation

```bash
# Update system packages
sudo apt update && sudo apt upgrade -y

# Configure interfaces
sudo raspi-config
# Interface Options > Camera, I2C, Remote GPIO
```

### 2. System Installation

```bash
# Clone repository
git clone https://github.com/mbrassey/pi-greeting-system
cd pi-greeting-system

# Verify system compatibility
./check_system.sh

# Install system components
./install.sh
```

### 3. System Configuration

Configuration parameters in `config.yml`:

```yaml
# Core configuration
camera:
  type: 'picamera'  # 'picamera' or 'usb'
  device: 0         # Camera device index
  resolution: [1280, 720]

greeting:
  enabled: true
  volume: 0.8
  language: 'en'
  custom_greetings:
    "John Doe": "Welcome back, sir!"
```

## Operation Guide

### Face Management

1. **Face Registration**
```bash
# Single image registration
./add_face.sh /path/to/photo.jpg "Person Name"

# Camera capture registration
./add_face.sh --capture "Person Name"

# Multi-angle registration
./add_face.sh --multi "Person Name"
```

2. **Face Database Management**
```bash
# List registered faces
./manage_faces.sh list-known

# Remove registration
./manage_faces.sh remove "Person Name"
```

### Unknown Face Processing

1. **Database Review**
```bash
# List unknown faces
./manage_faces.sh list-unknown
```

2. **Face Registration from Unknown**
```bash
# List unknown faces for ID reference
./manage_faces.sh list-unknown

# Register unknown face
./manage_faces.sh promote <face_id> "Person Name"
```

3. **Database Maintenance**
```bash
# Clean entries older than 30 days
./manage_faces.sh clean 30
```

### System Control

1. **Service Management**
```bash
# Start services
sudo systemctl start facial-recognition
sudo systemctl start facial-recognition-web

# Service control scripts
./service_start.sh
./service_stop.sh
./service_restart.sh
```

2. **System Monitoring**
```bash
# Service status
./service_status.sh

# Real-time monitoring
./monitor.sh

# Log inspection
tail -f /var/log/facial-recognition/system.log
```

3. **Web Interface**
```bash
# Interface access
http://<raspberry-pi-ip>:8080

# Default authentication
Username: admin
Password: admin  # Requires immediate change
```

### Performance Optimization

1. **Recognition Parameters**
```yaml
# config.yml
recognition:
  tolerance: 0.6    # Recognition strictness
  model: 'hog'      # Detection model: 'hog' (performance) or 'cnn' (accuracy)
  frame_rate: 30    # Processing rate
```

2. **Camera Configuration**
```yaml
camera:
  type: 'picamera'
  resolution: [1280, 720]
  flip_horizontal: false
  flip_vertical: false
```

3. **Resource Allocation**
```bash
# GPU memory allocation
vcgencmd get_mem gpu

# Adjust allocation in /boot/config.txt
gpu_mem=128
```

## Troubleshooting

### Camera Issues

1. **Connection Verification**
```bash
# Device enumeration
ls /dev/video*

# Pi Camera status
vcgencmd get_camera

# Camera diagnostics
./test_camera.sh
```

2. **Recognition Quality**
- Verify lighting conditions
- Implement multi-angle registration
- Adjust recognition tolerance
- Ensure lens cleanliness

### Audio Issues

1. **Output Verification**
```bash
# Audio diagnostics
./test_audio.sh

# Device enumeration
aplay -l

# Output testing
speaker-test -t wav
```

2. **Voice Synthesis**
- Adjust volume parameters
- Test alternative voices
- Verify output device selection

### System Issues

1. **Service Diagnostics**
```bash
# Service status inspection
systemctl status facial-recognition

# Detailed logging
journalctl -u facial-recognition -n 50
```

2. **Performance Issues**
- Reduce frame processing rate
- Switch to HOG detection
- Decrease resolution
- Terminate unnecessary processes

3. **Memory Management**
- Monitor usage: `./monitor.sh`
- Reduce frame buffer
- Implement database cleanup
- Consider memory upgrade

## Maintenance

1. **Data Backup**
```bash
# Create backup
./backup.sh

# Restore from backup
./backup.sh restore backup_20240101.tar.gz
```

2. **System Maintenance**
```bash
# Database cleanup
./manage_faces.sh clean 30

# System diagnostics
./monitor.sh

# System update
./update.sh
```

## Security Implementation

1. **Basic Security**
- Modify default credentials
- Enable HTTPS
- Implement network restrictions
- Maintain system updates

2. **Data Protection**
```yaml
# Security configuration
security:
  encrypt_faces: true
  session_timeout: 3600
  max_login_attempts: 5
```

3. **Access Control**
- Implement strong authentication
- Enable rate limiting
- Configure IP restrictions
- Set access permissions

## Support

- Issue tracking: GitHub Issues
- Updates: `./update.sh`
- Contributions: Pull requests
- Documentation: `/docs`

## License

MIT License - See LICENSE file for details. 