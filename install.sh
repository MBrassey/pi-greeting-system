#!/bin/bash

# Raspberry Pi Facial Recognition System Installation Script
# Handles complete system installation and dependency management

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

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   error "This script should not be run as root"
   info "Please run without sudo"
   exit 1
fi

# Verify Raspbian OS
if ! grep -q "Raspbian" /etc/os-release 2>/dev/null; then
    warning "This system may not be running Raspbian OS"
    warning "Some features might not work as expected"
fi

# Function to install Python 3.7 if needed
install_python37() {
    if ! command -v python3.7 &> /dev/null; then
        log "Installing Python 3.7..."
        
        # Install build dependencies
        sudo apt-get install -y build-essential tk-dev libncurses5-dev \
            libncursesw5-dev libreadline6-dev libdb5.3-dev libgdbm-dev \
            libsqlite3-dev libssl-dev libbz2-dev libexpat1-dev liblzma-dev \
            zlib1g-dev libffi-dev

        # Download and compile Python 3.7
        wget https://www.python.org/ftp/python/3.7.9/Python-3.7.9.tgz
        tar xzf Python-3.7.9.tgz
        cd Python-3.7.9
        ./configure --enable-optimizations
        make -j$(nproc)
        sudo make altinstall
        cd ..
        rm -rf Python-3.7.9*
        
        # Create symbolic links
        sudo update-alternatives --install /usr/bin/python3 python3 /usr/local/bin/python3.7 1
        sudo update-alternatives --install /usr/bin/pip3 pip3 /usr/local/bin/pip3.7 1
    else
        info "Python 3.7 is already installed"
    fi
}

# Function to install system dependencies
install_system_deps() {
    log "Installing system dependencies..."
    
    # Update package lists
    sudo apt-get update
    
    # Install required packages
    sudo apt-get install -y \
        python3-dev \
        python3-pip \
        python3-venv \
        build-essential \
        cmake \
        pkg-config \
        libjpeg-dev \
        libtiff5-dev \
        libjasper-dev \
        libpng-dev \
        libavcodec-dev \
        libavformat-dev \
        libswscale-dev \
        libv4l-dev \
        libxvidcore-dev \
        libx264-dev \
        libgtk-3-dev \
        libcanberra-gtk* \
        libatlas-base-dev \
        gfortran \
        libhdf5-dev \
        libhdf5-serial-dev \
        libhdf5-103 \
        libqt4-test \
        libqtgui4 \
        python3-opencv \
        espeak \
        espeak-data \
        alsa-utils \
        pulseaudio \
        git \
        wget \
        curl \
        v4l-utils \
        i2c-tools \
        raspi-config \
        rpi-update

    # Install picamera2 dependencies
    sudo apt-get install -y \
        python3-picamera2 \
        python3-libcamera \
        python3-kms++ \
        python3-prctl \
        libatlas-base-dev \
        ffmpeg \
        libopenjp2-7
}

# Function to configure camera and interfaces
configure_interfaces() {
    log "Configuring system interfaces..."
    
    # Enable camera
    if ! grep -q "start_x=1" /boot/config.txt; then
        echo "start_x=1" | sudo tee -a /boot/config.txt
    fi
    
    # Enable I2C
    if ! grep -q "dtparam=i2c_arm=on" /boot/config.txt; then
        echo "dtparam=i2c_arm=on" | sudo tee -a /boot/config.txt
    fi
    
    # Set GPU memory
    if ! grep -q "gpu_mem=" /boot/config.txt; then
        echo "gpu_mem=128" | sudo tee -a /boot/config.txt
    fi
    
    # Add user to required groups
    sudo usermod -a -G video,audio,gpio,i2c $USER
}

# Function to set up Python environment
setup_python_env() {
    log "Setting up Python environment..."
    
    # Create virtual environment
    python3.7 -m venv venv
    source venv/bin/activate
    
    # Upgrade pip
    pip install --upgrade pip
    
    # Install Python packages with specific versions for Raspbian
    pip install \
        numpy==1.21.6 \
        opencv-python==4.7.0.72 \
        face-recognition==1.3.0 \
        dlib==19.24.1 \
        Pillow==9.5.0 \
        pyttsx3==2.90 \
        Flask==2.0.3 \
        Flask-Login==0.6.2 \
        Flask-WTF==1.1.1 \
        Werkzeug==2.0.3 \
        PyYAML==6.0.1 \
        python-json-logger==2.0.7 \
        click==8.1.7 \
        schedule==1.2.0 \
        psutil==5.9.5 \
        cryptography==41.0.3 \
        requests==2.31.0 \
        picamera2==0.3.12 \
        imutils==0.5.4
}

# Function to verify installation
verify_installation() {
    log "Verifying installation..."
    
    # Verify Python
    if ! python3.7 --version &>/dev/null; then
        error "Python 3.7 installation failed"
        exit 1
    fi
    
    # Verify camera
    if ! vcgencmd get_camera &>/dev/null; then
        warning "Camera module not detected"
    fi
    
    # Verify audio
    if ! aplay -l &>/dev/null; then
        warning "Audio device not detected"
    fi
    
    # Verify face_recognition module
    source venv/bin/activate
    if ! python3.7 -c "import face_recognition" &>/dev/null; then
        error "face_recognition module installation failed"
        exit 1
    fi
    deactivate
}

# Main installation sequence
main() {
    log "Starting installation..."
    
    # Run system compatibility check
    ./check_system.sh || exit 1
    
    # Install Python 3.7
    install_python37
    
    # Install system dependencies
    install_system_deps
    
    # Configure interfaces
    configure_interfaces
    
    # Set up Python environment
    setup_python_env
    
    # Create required directories
    mkdir -p data/{known_faces,unknown_faces,logs,backups}
    mkdir -p templates static/faces ssl
    
    # Set permissions
    chmod +x *.sh
    chmod +x *.py
    
    # Verify installation
    verify_installation
    
    log "Installation completed successfully!"
    echo ""
    echo -e "${GREEN}=== Next Steps ===${NC}"
    echo "1. Reboot the system: sudo reboot"
    echo "2. Add faces using: ./add_face.sh"
    echo "3. Start the system: ./start.sh"
    echo ""
    echo -e "${YELLOW}Note: A system reboot is required to apply all changes${NC}"
}

# Run main installation
main 