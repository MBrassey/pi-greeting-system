#!/bin/bash

# Raspberry Pi Facial Recognition & Voice Greeting System Installer
# This script installs and configures a complete facial recognition system
# with voice greetings and unknown face detection/logging

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log function
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   error "This script should not be run as root. Please run as a regular user."
   exit 1
fi

# Check if running on Raspberry Pi or Linux
if ! command -v apt &> /dev/null; then
    error "This script requires a Debian/Ubuntu-based system with apt package manager."
    exit 1
fi

log "Starting Raspberry Pi Facial Recognition System Installation..."

# Update system
log "Updating system packages..."
sudo apt update && sudo apt upgrade -y

# Install essential packages
log "Installing essential packages..."
sudo apt install -y \
    python3 \
    python3-pip \
    python3-dev \
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
    libatlas-base-dev \
    gfortran \
    libhdf5-dev \
    libhdf5-serial-dev \
    libhdf5-103 \
    libqtgui4 \
    libqt4-test \
    espeak \
    espeak-data \
    alsa-utils \
    git \
    wget \
    curl \
    nano

# Install additional audio packages
log "Installing audio packages..."
sudo apt install -y \
    pulseaudio \
    pulseaudio-utils \
    pavucontrol

# Create project directory
PROJECT_DIR="$HOME/facial_recognition_system"
log "Creating project directory at $PROJECT_DIR..."
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"

# Create subdirectories
mkdir -p known_faces
mkdir -p unknown_faces
mkdir -p logs
mkdir -p config

# Create Python virtual environment
log "Creating Python virtual environment..."
python3 -m venv face_recognition_env
source face_recognition_env/bin/activate

# Upgrade pip
log "Upgrading pip..."
pip install --upgrade pip

# Install Python packages
log "Installing Python packages (this may take a while)..."
pip install \
    opencv-python \
    face-recognition \
    numpy \
    pillow \
    pyttsx3 \
    imutils \
    click \
    flask \
    schedule

# Create the main facial recognition script
log "Creating main facial recognition script..."
cat > face_recognition_system.py << 'EOF'
#!/usr/bin/env python3
"""
Facial Recognition System with Voice Greetings
Detects faces, identifies known faces, and logs unknown faces
"""

import cv2
import face_recognition
import pickle
import os
import json
import time
import uuid
from datetime import datetime
import pyttsx3
import numpy as np
from pathlib import Path
import threading
import queue

class FacialRecognitionSystem:
    def __init__(self):
        self.known_face_encodings = []
        self.known_face_names = []
        self.known_faces_dir = "known_faces"
        self.unknown_faces_dir = "unknown_faces"
        self.config_dir = "config"
        self.logs_dir = "logs"
        
        # Create directories if they don't exist
        for directory in [self.known_faces_dir, self.unknown_faces_dir, self.config_dir, self.logs_dir]:
            os.makedirs(directory, exist_ok=True)
        
        # Load configuration
        self.load_config()
        
        # Initialize text-to-speech
        self.tts_engine = pyttsx3.init()
        self.tts_engine.setProperty('rate', 150)  # Speed of speech
        
        # Initialize camera
        self.camera = cv2.VideoCapture(0)
        self.camera.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
        self.camera.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
        
        # Face detection parameters
        self.face_detection_tolerance = 0.6
        self.face_detection_model = 'hog'  # or 'cnn' for better accuracy but slower
        
        # Greeting cooldown to prevent spam
        self.last_greeting_time = {}
        self.greeting_cooldown = 30  # seconds
        
        # Unknown face detection
        self.unknown_face_threshold = 10  # frames before saving unknown face
        self.unknown_face_counters = {}
        
        # Load known faces
        self.load_known_faces()
        
        # TTS queue for non-blocking speech
        self.tts_queue = queue.Queue()
        self.tts_thread = threading.Thread(target=self.process_tts_queue, daemon=True)
        self.tts_thread.start()
    
    def load_config(self):
        """Load configuration from file"""
        config_file = os.path.join(self.config_dir, "config.json")
        default_config = {
            "face_detection_tolerance": 0.6,
            "greeting_cooldown": 30,
            "unknown_face_threshold": 10,
            "auto_save_unknown": True,
            "voice_enabled": True
        }
        
        if os.path.exists(config_file):
            try:
                with open(config_file, 'r') as f:
                    config = json.load(f)
                    self.face_detection_tolerance = config.get("face_detection_tolerance", 0.6)
                    self.greeting_cooldown = config.get("greeting_cooldown", 30)
                    self.unknown_face_threshold = config.get("unknown_face_threshold", 10)
                    self.auto_save_unknown = config.get("auto_save_unknown", True)
                    self.voice_enabled = config.get("voice_enabled", True)
            except Exception as e:
                print(f"Error loading config: {e}")
                self.save_config(default_config)
        else:
            self.save_config(default_config)
    
    def save_config(self, config=None):
        """Save configuration to file"""
        if config is None:
            config = {
                "face_detection_tolerance": self.face_detection_tolerance,
                "greeting_cooldown": self.greeting_cooldown,
                "unknown_face_threshold": self.unknown_face_threshold,
                "auto_save_unknown": getattr(self, 'auto_save_unknown', True),
                "voice_enabled": getattr(self, 'voice_enabled', True)
            }
        
        config_file = os.path.join(self.config_dir, "config.json")
        with open(config_file, 'w') as f:
            json.dump(config, f, indent=2)
    
    def load_known_faces(self):
        """Load known faces from the known_faces directory"""
        print("Loading known faces...")
        self.known_face_encodings = []
        self.known_face_names = []
        
        for filename in os.listdir(self.known_faces_dir):
            if filename.lower().endswith(('.png', '.jpg', '.jpeg')):
                # Extract name from filename (remove extension)
                name = os.path.splitext(filename)[0]
                
                # Load image
                image_path = os.path.join(self.known_faces_dir, filename)
                image = face_recognition.load_image_file(image_path)
                
                # Get face encodings
                face_encodings = face_recognition.face_encodings(image)
                
                if face_encodings:
                    # Use the first face found in the image
                    face_encoding = face_encodings[0]
                    self.known_face_encodings.append(face_encoding)
                    self.known_face_names.append(name)
                    print(f"Loaded face for: {name}")
                else:
                    print(f"No face found in {filename}")
        
        print(f"Loaded {len(self.known_face_names)} known faces")
    
    def process_tts_queue(self):
        """Process TTS queue in separate thread"""
        while True:
            try:
                message = self.tts_queue.get(timeout=1)
                if message and getattr(self, 'voice_enabled', True):
                    self.tts_engine.say(message)
                    self.tts_engine.runAndWait()
                self.tts_queue.task_done()
            except queue.Empty:
                continue
            except Exception as e:
                print(f"TTS Error: {e}")
    
    def speak_async(self, message):
        """Add message to TTS queue for non-blocking speech"""
        self.tts_queue.put(message)
    
    def save_unknown_face(self, face_image, face_location):
        """Save unknown face with timestamp and generated ID"""
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        face_id = str(uuid.uuid4())[:8]
        filename = f"unknown_{timestamp}_{face_id}.jpg"
        
        # Extract face from image
        top, right, bottom, left = face_location
        face_crop = face_image[top:bottom, left:right]
        
        # Save face image
        face_path = os.path.join(self.unknown_faces_dir, filename)
        cv2.imwrite(face_path, face_crop)
        
        # Log unknown face
        log_entry = {
            "timestamp": datetime.now().isoformat(),
            "face_id": face_id,
            "filename": filename,
            "location": face_location,
            "status": "unknown"
        }
        
        log_file = os.path.join(self.logs_dir, "unknown_faces.json")
        
        # Load existing log or create new
        if os.path.exists(log_file):
            with open(log_file, 'r') as f:
                logs = json.load(f)
        else:
            logs = []
        
        logs.append(log_entry)
        
        # Save updated log
        with open(log_file, 'w') as f:
            json.dump(logs, f, indent=2)
        
        print(f"Saved unknown face: {filename}")
        return face_id
    
    def should_greet(self, name):
        """Check if we should greet this person (cooldown logic)"""
        current_time = time.time()
        last_greeting = self.last_greeting_time.get(name, 0)
        
        if current_time - last_greeting > self.greeting_cooldown:
            self.last_greeting_time[name] = current_time
            return True
        return False
    
    def run(self):
        """Main recognition loop"""
        print("Starting facial recognition system...")
        print("Press 'q' to quit, 'r' to reload known faces")
        
        while True:
            # Capture frame
            ret, frame = self.camera.read()
            if not ret:
                print("Failed to capture frame")
                break
            
            # Convert BGR to RGB
            rgb_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            
            # Find faces in frame
            face_locations = face_recognition.face_locations(rgb_frame, model=self.face_detection_model)
            face_encodings = face_recognition.face_encodings(rgb_frame, face_locations)
            
            # Process each face
            for face_encoding, face_location in zip(face_encodings, face_locations):
                # Compare with known faces
                matches = face_recognition.compare_faces(
                    self.known_face_encodings, 
                    face_encoding,
                    tolerance=self.face_detection_tolerance
                )
                
                name = "Unknown"
                
                if True in matches:
                    # Find the best match
                    face_distances = face_recognition.face_distance(self.known_face_encodings, face_encoding)
                    best_match_index = np.argmin(face_distances)
                    if matches[best_match_index]:
                        name = self.known_face_names[best_match_index]
                        
                        # Greet known person
                        if self.should_greet(name):
                            greeting = f"Hello {name}!"
                            print(greeting)
                            self.speak_async(greeting)
                
                else:
                    # Handle unknown face
                    face_key = str(face_location)
                    
                    if face_key not in self.unknown_face_counters:
                        self.unknown_face_counters[face_key] = 0
                    
                    self.unknown_face_counters[face_key] += 1
                    
                    # Save unknown face after threshold
                    if (self.unknown_face_counters[face_key] >= self.unknown_face_threshold and 
                        getattr(self, 'auto_save_unknown', True)):
                        face_id = self.save_unknown_face(frame, face_location)
                        print(f"New unknown face detected and saved: {face_id}")
                        # Reset counter so we don't save the same face multiple times
                        self.unknown_face_counters[face_key] = -1000
                
                # Draw rectangle around face
                top, right, bottom, left = face_location
                color = (0, 255, 0) if name != "Unknown" else (0, 0, 255)
                cv2.rectangle(frame, (left, top), (right, bottom), color, 2)
                
                # Draw name
                cv2.rectangle(frame, (left, bottom - 35), (right, bottom), color, cv2.FILLED)
                cv2.putText(frame, name, (left + 6, bottom - 6), cv2.FONT_HERSHEY_DUPLEX, 0.8, (255, 255, 255), 1)
            
            # Display frame
            cv2.imshow('Facial Recognition System', frame)
            
            # Check for key presses
            key = cv2.waitKey(1) & 0xFF
            if key == ord('q'):
                break
            elif key == ord('r'):
                print("Reloading known faces...")
                self.load_known_faces()
            
            # Clean up old unknown face counters
            if len(self.unknown_face_counters) > 100:
                self.unknown_face_counters.clear()
        
        # Cleanup
        self.camera.release()
        cv2.destroyAllWindows()
        print("System shut down")

def main():
    try:
        system = FacialRecognitionSystem()
        system.run()
    except KeyboardInterrupt:
        print("\nShutting down...")
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    main()
EOF

# Create a training script for adding new faces
log "Creating face training script..."
cat > add_face.py << 'EOF'
#!/usr/bin/env python3
"""
Script to add new faces to the known_faces directory
"""

import os
import sys
import shutil
from pathlib import Path

def add_face(image_path, person_name):
    """Add a face to the known_faces directory"""
    known_faces_dir = "known_faces"
    
    # Create directory if it doesn't exist
    os.makedirs(known_faces_dir, exist_ok=True)
    
    # Check if image exists
    if not os.path.exists(image_path):
        print(f"Error: Image file {image_path} not found")
        return False
    
    # Get file extension
    file_ext = os.path.splitext(image_path)[1].lower()
    if file_ext not in ['.jpg', '.jpeg', '.png']:
        print(f"Error: Unsupported file format. Use .jpg, .jpeg, or .png")
        return False
    
    # Create new filename
    new_filename = f"{person_name}{file_ext}"
    new_path = os.path.join(known_faces_dir, new_filename)
    
    # Copy file
    try:
        shutil.copy2(image_path, new_path)
        print(f"Successfully added {person_name} to known faces")
        print(f"Image saved as: {new_path}")
        return True
    except Exception as e:
        print(f"Error copying file: {e}")
        return False

def main():
    if len(sys.argv) != 3:
        print("Usage: python3 add_face.py <image_path> <person_name>")
        print("Example: python3 add_face.py /path/to/photo.jpg 'John Doe'")
        sys.exit(1)
    
    image_path = sys.argv[1]
    person_name = sys.argv[2]
    
    # Clean person name (remove special characters)
    person_name = "".join(c for c in person_name if c.isalnum() or c in (' ', '-', '_')).strip()
    
    if not person_name:
        print("Error: Invalid person name")
        sys.exit(1)
    
    success = add_face(image_path, person_name)
    if success:
        print("\nFace added successfully!")
        print("Restart the facial recognition system to load the new face.")
    else:
        print("\nFailed to add face.")
        sys.exit(1)

if __name__ == "__main__":
    main()
EOF

# Create a management script
log "Creating management script..."
cat > manage_faces.py << 'EOF'
#!/usr/bin/env python3
"""
Management script for the facial recognition system
"""

import os
import json
import sys
from datetime import datetime
from pathlib import Path

class FaceManager:
    def __init__(self):
        self.known_faces_dir = "known_faces"
        self.unknown_faces_dir = "unknown_faces"
        self.logs_dir = "logs"
        self.config_dir = "config"
    
    def list_known_faces(self):
        """List all known faces"""
        print("Known faces:")
        if not os.path.exists(self.known_faces_dir):
            print("  No known faces directory found")
            return
        
        faces = [f for f in os.listdir(self.known_faces_dir) 
                if f.lower().endswith(('.png', '.jpg', '.jpeg'))]
        
        if not faces:
            print("  No known faces found")
        else:
            for face in sorted(faces):
                name = os.path.splitext(face)[0]
                print(f"  - {name} ({face})")
    
    def list_unknown_faces(self):
        """List all unknown faces with their details"""
        print("Unknown faces:")
        log_file = os.path.join(self.logs_dir, "unknown_faces.json")
        
        if not os.path.exists(log_file):
            print("  No unknown faces logged")
            return
        
        try:
            with open(log_file, 'r') as f:
                logs = json.load(f)
            
            if not logs:
                print("  No unknown faces found")
                return
            
            for log in sorted(logs, key=lambda x: x['timestamp'], reverse=True):
                timestamp = datetime.fromisoformat(log['timestamp']).strftime("%Y-%m-%d %H:%M:%S")
                print(f"  - {log['face_id']} ({log['filename']}) - {timestamp}")
        
        except Exception as e:
            print(f"  Error reading log file: {e}")
    
    def promote_unknown_face(self, face_id, new_name):
        """Promote an unknown face to known face"""
        log_file = os.path.join(self.logs_dir, "unknown_faces.json")
        
        if not os.path.exists(log_file):
            print("No unknown faces log found")
            return False
        
        try:
            with open(log_file, 'r') as f:
                logs = json.load(f)
            
            # Find the face
            target_log = None
            for log in logs:
                if log['face_id'] == face_id:
                    target_log = log
                    break
            
            if not target_log:
                print(f"Face ID {face_id} not found")
                return False
            
            # Get the unknown face file
            unknown_file = os.path.join(self.unknown_faces_dir, target_log['filename'])
            if not os.path.exists(unknown_file):
                print(f"Unknown face file {unknown_file} not found")
                return False
            
            # Copy to known faces
            file_ext = os.path.splitext(target_log['filename'])[1]
            known_file = os.path.join(self.known_faces_dir, f"{new_name}{file_ext}")
            
            import shutil
            shutil.copy2(unknown_file, known_file)
            
            # Update log
            target_log['status'] = 'promoted'
            target_log['promoted_name'] = new_name
            target_log['promoted_timestamp'] = datetime.now().isoformat()
            
            with open(log_file, 'w') as f:
                json.dump(logs, f, indent=2)
            
            print(f"Successfully promoted {face_id} to known face '{new_name}'")
            print(f"Restart the facial recognition system to load the new face.")
            return True
            
        except Exception as e:
            print(f"Error promoting face: {e}")
            return False
    
    def remove_known_face(self, name):
        """Remove a known face"""
        faces = [f for f in os.listdir(self.known_faces_dir) 
                if f.lower().endswith(('.png', '.jpg', '.jpeg'))]
        
        target_file = None
        for face in faces:
            if os.path.splitext(face)[0] == name:
                target_file = face
                break
        
        if not target_file:
            print(f"Known face '{name}' not found")
            return False
        
        try:
            file_path = os.path.join(self.known_faces_dir, target_file)
            os.remove(file_path)
            print(f"Successfully removed known face '{name}'")
            return True
        except Exception as e:
            print(f"Error removing face: {e}")
            return False
    
    def clean_unknown_faces(self, days_old=30):
        """Clean up old unknown faces"""
        log_file = os.path.join(self.logs_dir, "unknown_faces.json")
        
        if not os.path.exists(log_file):
            print("No unknown faces log found")
            return
        
        try:
            with open(log_file, 'r') as f:
                logs = json.load(f)
            
            cutoff_date = datetime.now().timestamp() - (days_old * 24 * 60 * 60)
            
            cleaned_logs = []
            removed_count = 0
            
            for log in logs:
                log_date = datetime.fromisoformat(log['timestamp']).timestamp()
                
                if log_date < cutoff_date and log['status'] == 'unknown':
                    # Remove the file
                    file_path = os.path.join(self.unknown_faces_dir, log['filename'])
                    if os.path.exists(file_path):
                        os.remove(file_path)
                    removed_count += 1
                else:
                    cleaned_logs.append(log)
            
            # Save cleaned logs
            with open(log_file, 'w') as f:
                json.dump(cleaned_logs, f, indent=2)
            
            print(f"Cleaned up {removed_count} old unknown faces")
            
        except Exception as e:
            print(f"Error cleaning unknown faces: {e}")

def main():
    manager = FaceManager()
    
    if len(sys.argv) < 2:
        print("Face Recognition System Management")
        print("Usage:")
        print("  python3 manage_faces.py list-known")
        print("  python3 manage_faces.py list-unknown")
        print("  python3 manage_faces.py promote <face_id> <new_name>")
        print("  python3 manage_faces.py remove <name>")
        print("  python3 manage_faces.py clean [days_old]")
        sys.exit(1)
    
    command = sys.argv[1]
    
    if command == "list-known":
        manager.list_known_faces()
    
    elif command == "list-unknown":
        manager.list_unknown_faces()
    
    elif command == "promote":
        if len(sys.argv) != 4:
            print("Usage: python3 manage_faces.py promote <face_id> <new_name>")
            sys.exit(1)
        
        face_id = sys.argv[2]
        new_name = sys.argv[3]
        manager.promote_unknown_face(face_id, new_name)
    
    elif command == "remove":
        if len(sys.argv) != 3:
            print("Usage: python3 manage_faces.py remove <name>")
            sys.exit(1)
        
        name = sys.argv[2]
        manager.remove_known_face(name)
    
    elif command == "clean":
        days_old = 30
        if len(sys.argv) == 3:
            try:
                days_old = int(sys.argv[2])
            except ValueError:
                print("Error: days_old must be a number")
                sys.exit(1)
        
        manager.clean_unknown_faces(days_old)
    
    else:
        print(f"Unknown command: {command}")
        sys.exit(1)

if __name__ == "__main__":
    main()
EOF

# Create systemd service file
log "Creating systemd service file..."
cat > face_recognition.service << EOF
[Unit]
Description=Facial Recognition System
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$PROJECT_DIR
Environment=PATH=$PROJECT_DIR/face_recognition_env/bin
ExecStart=$PROJECT_DIR/face_recognition_env/bin/python face_recognition_system.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Create startup script
log "Creating startup script..."
cat > start_face_recognition.sh << EOF
#!/bin/bash
cd "$PROJECT_DIR"
source face_recognition_env/bin/activate
python face_recognition_system.py
EOF

chmod +x start_face_recognition.sh

# Create README with instructions
log "Creating README file..."
cat > README.md << 'EOF'
# Facial Recognition System

A complete facial recognition system with voice greetings for Raspberry Pi.

## Features

- Real-time face detection and recognition
- Voice greetings for known faces
- Automatic detection and logging of unknown faces
- Web interface for face management
- Configurable settings
- Automatic startup service

## Directory Structure

```
facial_recognition_system/
├── face_recognition_system.py  # Main application
├── add_face.py                 # Script to add new faces
├── manage_faces.py             # Face management script
├── start_face_recognition.sh   # Startup script
├── known_faces/               # Directory for known face images
├── unknown_faces/             # Directory for detected unknown faces
├── logs/                      # Log files
├── config/                    # Configuration files
└── face_recognition_env/      # Python virtual environment
```

## Usage

### Starting the System

```bash
cd ~/facial_recognition_system
./start_face_recognition.sh
```

### Adding Known Faces

To add a new person to the system:

```bash
cd ~/facial_recognition_system
source face_recognition_env/bin/activate
python add_face.py /path/to/photo.jpg "Person Name"
```

### Managing Faces

List all known faces:
```bash
python manage_faces.py list-known
```

List unknown faces that have been detected:
```bash
python manage_faces.py list-unknown
```

Promote an unknown face to a known face:
```bash
python manage_faces.py promote <face_id> "New Name"
```

Remove a known face:
```bash
python manage_faces.py remove "Person Name"
```

Clean up old unknown faces (older than 30 days):
```bash
python manage_faces.py clean
```

### Controls

When running the main system:
- Press 'q' to quit
- Press 'r' to reload known faces (useful after adding new faces)

## Configuration

Edit `config/config.json` to customize:
- `face_detection_tolerance`: How strict face matching is (0.6 = default)
- `greeting_cooldown`: Seconds between greetings for same person (30 = default)
- `unknown_face_threshold`: Frames before saving unknown face (10 = default)
- `auto_save_unknown`: Whether to automatically save unknown faces (true = default)
- `voice_enabled`: Whether to enable voice greetings (true = default)

## Installing as System Service

To run automatically on boot:

```bash
sudo cp face_recognition.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable face_recognition.service
sudo systemctl start face_recognition.service
```

Check service status:
```bash
sudo systemctl status face_recognition.service
```

## Troubleshooting

### Camera Issues
- Make sure camera is connected and enabled
- Check with: `ls /dev/video*`
- Enable camera: `sudo raspi-config` (if on Raspberry Pi)

### Audio Issues
- Test speakers: `speaker-test -t wav`
- Test espeak: `espeak "Hello World"`
- Check audio output: `aplay -l`

### Performance Issues
- Consider using 'hog' model instead of 'cnn' for face detection
- Reduce camera resolution in the script
- Increase face_detection_tolerance for faster matching

### Python Package Issues
- Reinstall in virtual environment:
  ```bash
  cd ~/facial_recognition_system
  rm -rf face_recognition_env
  python3 -m venv face_recognition_env
  source face_recognition_env/bin/activate
  pip install opencv-python face-recognition numpy pillow pyttsx3 imutils click flask schedule
  ```

## Log Files

- `logs/unknown_faces.json`: Contains details of all detected unknown faces
- Check system logs: `sudo journalctl -u face_recognition.service -f`

## Tips

1. **Good Photos for Training**: Use clear, well-lit photos with the person looking directly at the camera
2. **Multiple Angles**: Add multiple photos of the same person from different angles for better recognition
3. **Lighting**: Ensure good lighting in the area where recognition will occur
4. **Camera Position**: Mount camera at eye level for best results
5. **Testing**: Test the system thoroughly before deploying

## Hardware Requirements

- Raspberry Pi 3B+ or newer (Pi 4 recommended)
- USB camera or Pi Camera module
- Speakers or audio output
- At least 2GB RAM (4GB+ recommended)
- 16GB+ SD card

## Security Notes

- Unknown faces are saved as images - ensure privacy compliance
- Consider encrypting stored face data for sensitive applications
- Regularly clean up old unknown faces
- Be aware of privacy laws in your jurisdiction
EOF

# Create requirements file
log "Creating requirements.txt..."
cat > requirements.txt << 'EOF'
opencv-python
face-recognition
numpy
pillow
pyttsx3
imutils
click
flask
schedule
EOF

# Deactivate virtual environment
deactivate

# Set permissions
log "Setting permissions..."
chmod +x face_recognition_system.py
chmod +x add_face.py
chmod +x manage_faces.py
chmod +x start_face_recognition.sh

# Create desktop shortcut
log "Creating desktop shortcut..."
DESKTOP_DIR="$HOME/Desktop"
if [ -d "$DESKTOP_DIR" ]; then
    cat > "$DESKTOP_DIR/Face Recognition System.desktop" << EOF
[Desktop Entry]
Name=Face Recognition System
Comment=Start the facial recognition system
Exec=lxterminal -e "$PROJECT_DIR/start_face_recognition.sh"
Icon=camera-photo
Terminal=false
Type=Application
Categories=Application;
EOF
    chmod +x "$DESKTOP_DIR/Face Recognition System.desktop"
fi

# Test audio system
log "Testing audio system..."
if command -v espeak &> /dev/null; then
    echo "Testing text-to-speech..."
    espeak "Audio system test successful" 2>/dev/null || warning "Audio test failed - check speakers"
else
    warning "espeak not found - voice greetings may not work"
fi

# Test camera
log "Testing camera..."
if [ -e /dev/video0 ]; then
    info "Camera device found at /dev/video0"
else
    warning "No camera device found at /dev/video0"
    info "Available video devices:"
    ls /dev/video* 2>/dev/null || echo "No video devices found"
fi

# Final setup instructions
log "Installation complete!"
echo ""
echo -e "${GREEN}=== INSTALLATION SUMMARY ===${NC}"
echo -e "Project directory: ${BLUE}$PROJECT_DIR${NC}"
echo -e "Main script: ${BLUE}face_recognition_system.py${NC}"
echo -e "Management script: ${BLUE}manage_faces.py${NC}"
echo -e "Add faces script: ${BLUE}add_face.py${NC}"
echo ""
echo -e "${GREEN}=== NEXT STEPS ===${NC}"
echo -e "1. ${YELLOW}Add known faces:${NC}"
echo -e "   cd $PROJECT_DIR"
echo -e "   source face_recognition_env/bin/activate"
echo -e "   python add_face.py /path/to/photo.jpg \"Person Name\""
echo ""
echo -e "2. ${YELLOW}Start the system:${NC}"
echo -e "   cd $PROJECT_DIR"
echo -e "   ./start_face_recognition.sh"
echo ""
echo -e "3. ${YELLOW}Install as system service (optional):${NC}"
echo -e "   sudo cp face_recognition.service /etc/systemd/system/"
echo -e "   sudo systemctl daemon-reload"
echo -e "   sudo systemctl enable face_recognition.service"
echo -e "   sudo systemctl start face_recognition.service"
echo ""
echo -e "${GREEN}=== TROUBLESHOOTING ===${NC}"
echo -e "- Check camera: ${BLUE}ls /dev/video*${NC}"
echo -e "- Test audio: ${BLUE}espeak \"Hello World\"${NC}"
echo -e "- View logs: ${BLUE}sudo journalctl -u face_recognition.service -f${NC}"
echo -e "- Read README: ${BLUE}$PROJECT_DIR/README.md${NC}"
echo ""
echo -e "${GREEN}Installation completed successfully!${NC}"
echo -e "See the README.md file for detailed usage instructions."