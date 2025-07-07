#!/bin/bash

# Audio Test Script for Raspberry Pi Facial Recognition System
# Tests audio output and text-to-speech functionality

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

# Function to test audio devices
test_audio_devices() {
    log "Testing audio devices..."
    
    # Check for audio devices
    if ! command -v aplay &> /dev/null; then
        error "aplay not found. Please install alsa-utils"
        return 1
    }
    
    # List audio devices
    info "Available audio devices:"
    aplay -l
    
    # Check default audio device
    info "Default audio device:"
    if ! aplay -L | grep -q "default"; then
        error "No default audio device found"
        return 1
    fi
    aplay -L | grep "default" -A 2
    
    # Check pulseaudio
    if command -v pulseaudio &> /dev/null; then
        info "PulseAudio status:"
        pulseaudio --check
        if [ $? -eq 0 ]; then
            echo "PulseAudio is running"
        else
            warning "PulseAudio is not running"
            info "Starting PulseAudio..."
            pulseaudio --start
        fi
    else
        warning "PulseAudio not installed"
    fi
    
    return 0
}

# Function to test audio output
test_audio_output() {
    log "Testing audio output..."
    
    # Generate test tone
    info "Playing test tone..."
    if ! speaker-test -t wav -c 2 -l 1 > /dev/null 2>&1; then
        error "Failed to play test tone"
        return 1
    fi
    
    # Ask for confirmation
    echo -n "Did you hear the test tone? (y/n) "
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        info "Audio output test successful"
        return 0
    else
        error "Audio output test failed"
        return 1
    fi
}

# Function to test text-to-speech
test_tts() {
    log "Testing text-to-speech..."
    
    # Check for espeak
    if ! command -v espeak &> /dev/null; then
        error "espeak not found. Please install espeak"
        return 1
    fi
    
    # Test Python TTS
    info "Testing Python text-to-speech..."
    python3 - << EOF
import sys
try:
    import pyttsx3
    engine = pyttsx3.init()
    
    # Get available voices
    voices = engine.getProperty('voices')
    print(f"Available voices: {len(voices)}")
    
    # Get current properties
    rate = engine.getProperty('rate')
    volume = engine.getProperty('volume')
    print(f"Current rate: {rate}")
    print(f"Current volume: {volume}")
    
    # Test speech
    engine.say("This is a test of the text to speech system")
    engine.runAndWait()
    
    sys.exit(0)
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
EOF
    
    if [ $? -ne 0 ]; then
        error "Python TTS test failed"
        return 1
    fi
    
    # Ask for confirmation
    echo -n "Did you hear the test message? (y/n) "
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        info "TTS test successful"
        return 0
    else
        error "TTS test failed"
        return 1
    fi
}

# Function to test volume control
test_volume() {
    log "Testing volume control..."
    
    # Check for amixer
    if ! command -v amixer &> /dev/null; then
        error "amixer not found. Please install alsa-utils"
        return 1
    }
    
    # Get current volume
    current_volume=$(amixer get Master | grep -o "[0-9]*%" | head -1)
    info "Current volume: $current_volume"
    
    # Test volume levels
    for volume in 50 75 100; do
        info "Setting volume to ${volume}%..."
        amixer set Master "${volume}%" > /dev/null 2>&1
        
        info "Playing test tone at ${volume}%..."
        speaker-test -t wav -c 2 -l 1 > /dev/null 2>&1
        
        echo -n "Did you hear the difference in volume? (y/n) "
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            warning "Volume control may not be working correctly"
        fi
    done
    
    # Restore original volume
    amixer set Master "${current_volume}" > /dev/null 2>&1
    
    return 0
}

# Function to check audio configuration
check_audio_config() {
    log "Checking audio configuration..."
    
    # Check ALSA config
    if [ -f "/etc/asound.conf" ]; then
        info "ALSA configuration found:"
        cat /etc/asound.conf
    else
        info "No system-wide ALSA configuration found"
    fi
    
    # Check user ALSA config
    if [ -f "$HOME/.asoundrc" ]; then
        info "User ALSA configuration found:"
        cat "$HOME/.asoundrc"
    fi
    
    # Check PulseAudio config
    if [ -f "/etc/pulse/default.pa" ]; then
        info "PulseAudio configuration found"
    fi
    
    # Check audio groups
    info "Checking audio groups..."
    groups | grep -q "audio"
    if [ $? -eq 0 ]; then
        info "User is in audio group"
    else
        warning "User is not in audio group"
        info "Consider adding user to audio group:"
        echo "sudo usermod -a -G audio $USER"
    fi
}

# Main test sequence
log "Starting audio tests..."

# Run tests
test_audio_devices
devices_result=$?

test_audio_output
output_result=$?

test_tts
tts_result=$?

test_volume
volume_result=$?

check_audio_config

# Print summary
echo ""
echo -e "${GREEN}=== TEST SUMMARY ===${NC}"
echo -e "Audio Devices: $([ $devices_result -eq 0 ] && echo "${GREEN}Working${NC}" || echo "${RED}Failed${NC}")"
echo -e "Audio Output: $([ $output_result -eq 0 ] && echo "${GREEN}Working${NC}" || echo "${RED}Failed${NC}")"
echo -e "Text-to-Speech: $([ $tts_result -eq 0 ] && echo "${GREEN}Working${NC}" || echo "${RED}Failed${NC}")"
echo -e "Volume Control: $([ $volume_result -eq 0 ] && echo "${GREEN}Working${NC}" || echo "${RED}Failed${NC}")"

echo ""
echo -e "${BLUE}Recommendations:${NC}"
if [ $devices_result -ne 0 ] || [ $output_result -ne 0 ]; then
    echo "1. Check audio connections and cables"
    echo "2. Verify audio device is selected in raspi-config"
    echo "3. Check volume levels in system settings"
    echo "4. Try running: sudo alsactl restore"
fi

if [ $tts_result -ne 0 ]; then
    echo "5. Verify espeak is installed: sudo apt install espeak"
    echo "6. Check Python TTS dependencies are installed"
fi

if [ $volume_result -ne 0 ]; then
    echo "7. Check volume control permissions"
    echo "8. Verify ALSA mixer settings"
fi

echo ""
echo -e "${YELLOW}Note: Some issues may require a system reboot to resolve${NC}" 