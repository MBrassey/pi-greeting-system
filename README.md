# Raspberry Pi Facial Recognition System

Real-time facial recognition system for Raspberry Pi that implements face detection, recognition, and voice synthesis for greetings. Includes a web interface for system management.

## Core Components

- **Face Processing**
  - Face detection: HOG or CNN models
  - Face recognition with adjustable tolerance
  - Compatible with USB webcams and Pi Camera modules
  - IMX519 sensor optimization
  - Configurable resolution and frame rate

- **Audio Output**
  - Text-to-speech synthesis
  - Multiple language support
  - Bluetooth audio compatibility
  - Configurable greeting intervals

- **Web Interface**
  - System monitoring dashboard
  - Face database management
  - System metrics
  - SSL/TLS support
  - Responsive web design

- **Security**
  - Face data encryption (optional)
  - IP address filtering
  - Session management
  - Login attempt limiting
  - HTTPS configuration

- **System Functions**
  - Unknown face detection and storage
  - Face image quality validation
  - Multiple angle face registration
  - Automated backups
  - Performance tuning options

## Hardware Requirements

**Minimum:**
- Raspberry Pi 3B+ or newer
- 2GB RAM
- 16GB SD card
- Camera (USB or Pi Camera Module)
- Audio output device

**Recommended:**
- Raspberry Pi 4 (4GB/8GB RAM)
- Pi Camera Module 3 (IMX519)
- 7" Raspberry Pi Display
- Bluetooth/USB Speaker
- 64GB SD Card
- Sufficient lighting (min. 200 lux)

## Installation

1. **System Setup**
```bash
# Update packages
sudo apt update && sudo apt upgrade -y

# Enable interfaces
sudo raspi-config
# Enable: Camera, I2C, Remote GPIO
```

2. **Software Installation**
```bash
git clone https://github.com/yourusername/pi-greeting-system
cd pi-greeting-system
./install.sh
```

3. **Initial Configuration**
```bash
# Configure web interface
./setup_web.sh

# Edit system settings
nano config.yml
```

## Configuration

Key settings in `config.yml`:

```yaml
recognition:
  tolerance: 0.6    # Face matching threshold (0.4-0.6)
  model: 'hog'      # Detection model: 'hog' or 'cnn'
  frame_rate: 30    # Frames per second
  resolution: [1920, 1080]

greeting:
  enabled: true
  volume: 0.8
  language: 'en'
  custom_greetings:
    "John Doe": "Welcome back, sir!"

security:
  encrypt_faces: false
  allowed_ips: []
  session_timeout: 3600
```

## Usage

### Face Database Management

1. **Face Registration**
```bash
# Register from file
./manage_faces.sh add /path/to/photo.jpg "Person Name"

# Register via camera
./manage_faces.sh capture "Person Name"

# Register multiple angles
./manage_faces.sh multi "Person Name"
```

2. **Database Operations**
```bash
# List registered faces
./manage_faces.sh list-known

# Remove face
./manage_faces.sh remove "Person Name"

# Remove old unknown faces
./manage_faces.sh clean 30
```

### System Operations

1. **System Control**
```bash
# Start with display output
./start.sh

# Run as service
sudo ./install_service.sh
sudo systemctl start facial-recognition
```

2. **Web Interface Access**
```bash
# Interface URL
http://<raspberry-pi-ip>:8080

# Authentication
Username: admin
Password: [set during installation]
```

3. **System Monitoring**
```bash
# View status
./monitor.sh

# View logs
tail -f /var/log/facial-recognition/system.log
```

### System Maintenance

1. **Backup Operations**
```bash
# Create backup
./backup.sh

# Restore backup
./backup.sh restore backup_20240101.tar.gz
```

2. **System Updates**
```bash
./update.sh
```

## Troubleshooting

### Camera
- Execute `./test_camera.sh` for diagnostics
- Verify interface activation
- Check lighting conditions (200+ lux recommended)
- Ensure clean lens surface

### Audio
- Execute `./test_audio.sh` for diagnostics
- Verify audio device connections
- Check audio device selection
- Verify system volume configuration

### Recognition
- Adjust tolerance value in config.yml
- Implement multiple angle registration
- Ensure adequate lighting
- Test CNN model for improved accuracy

### Performance
- Lower resolution/frame rate
- Use HOG detection model
- Remove old face data
- Monitor resource usage with `./monitor.sh`

## Security Configuration

1. **Basic Setup**
- Update default credentials
- Configure HTTPS
- Set IP allowlist
- Maintain system updates

2. **Data Security**
- Enable face encryption
- Configure backup schedule
- Set file permissions (600 for keys, 644 for data)
- Schedule security audits

## Development

- Issue tracker: GitHub Issues
- Documentation: `/docs`
- Pull requests: Accepted with tests
- Discussions: GitHub Discussions

## License

`pi-greeting-system` is published under the **CC0_1.0_Universal** license.

> The Creative Commons CC0 Public Domain Dedication waives copyright interest in a work you've created and dedicates it to the world-wide public domain. Use CC0 to opt out of copyright entirely and ensure your work has the widest reach. As with the Unlicense and typical software licenses, CC0 disclaims warranties. CC0 is very similar to the Unlicense.