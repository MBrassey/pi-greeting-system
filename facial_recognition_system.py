#!/usr/bin/env python3
"""
Raspberry Pi Facial Recognition System
Core system module implementing real-time face detection, recognition, and voice synthesis
"""

import cv2
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
from PIL import Image
from cryptography.fernet import Fernet
import face_recognition

class FacialRecognitionSystem:
    def __init__(self):
        """Initialize system components and configuration"""
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
        """Initialize core system components and state variables"""
        self.setup_storage()
        self.setup_camera()
        self.setup_audio()
        self.setup_face_recognition()
        self.setup_encryption()
        
        # Initialize state variables
        self.running = True
        self.show_stats = False
        self.frame_times = []
        self.last_greeting_time = {}
        self.unknown_face_counters = {}
    
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
        """Initialize camera with USB webcam device"""
        device = '/dev/video0'  # Default to first USB camera
        
        try:
            self.logger.info(f"Opening USB camera on {device}")
            self.camera = cv2.VideoCapture(device)
            if self.camera.isOpened():
                # Test frame capture
                ret, frame = self.camera.read()
                if ret and frame is not None:
                    self.logger.info("Successfully opened camera")
                    # Set camera properties
                    self.camera.set(cv2.CAP_PROP_FRAME_WIDTH, self.config['recognition']['resolution'][0])
                    self.camera.set(cv2.CAP_PROP_FRAME_HEIGHT, self.config['recognition']['resolution'][1])
                    self.camera.set(cv2.CAP_PROP_FPS, self.config['recognition']['frame_rate'])
                    self.camera.set(cv2.CAP_PROP_AUTOFOCUS, 1)
                    self.camera.set(cv2.CAP_PROP_AUTO_EXPOSURE, 1)
                    
                    # Create window
                    cv2.namedWindow('Facial Recognition System', cv2.WINDOW_NORMAL)
                    cv2.moveWindow('Facial Recognition System', 0, 0)
                    return
                else:
                    self.logger.error("Could not read frame from camera")
                    self.camera.release()
            else:
                self.logger.error("Could not open camera")
        except Exception as e:
            self.logger.error(f"Error initializing camera: {str(e)}")
            if hasattr(self, 'camera'):
                self.camera.release()
        
        self.logger.error("Could not initialize camera!")
        sys.exit(1)
    
    def setup_audio(self):
        """Initialize text-to-speech synthesis engine"""
        try:
            self.logger.info("Initializing audio system...")
            
            # Try to set default audio device to Bluetooth
            try:
                import subprocess
                
                # Get list of audio devices
                devices = subprocess.check_output(['pactl', 'list', 'short', 'sinks']).decode().strip().split('\n')
                print("\nAvailable audio devices:")
                for device in devices:
                    print(device)
                
                # Look for Bluetooth device
                bluetooth_device = None
                for device in devices:
                    if 'bluetooth' in device.lower():
                        bluetooth_device = device.split('\t')[0]
                        break
                
                if bluetooth_device:
                    # Set as default audio device
                    subprocess.run(['pactl', 'set-default-sink', bluetooth_device])
                    print(f"\nSet audio output to Bluetooth device: {bluetooth_device}")
                else:
                    print("\nNo Bluetooth audio device found, using default audio output")
            except Exception as e:
                print(f"\nCould not set Bluetooth audio device: {e}")
                print("Using default audio output")
            
            # Initialize text-to-speech
            self.tts_engine = pyttsx3.init()
            self.tts_engine.setProperty('rate', 150)  # Default rate
            self.tts_engine.setProperty('volume', 1.0)  # Full volume
            
            # Get available voices
            voices = self.tts_engine.getProperty('voices')
            print("\nAvailable voices:")
            for voice in voices:
                print(f"- {voice.name} ({voice.id})")
            
            # Try to set a better voice if available
            for voice in voices:
                if "english" in voice.name.lower():
                    self.tts_engine.setProperty('voice', voice.id)
                    print(f"\nSet voice to: {voice.name}")
                    break
            
            # Test audio
            print("\nTesting audio output...")
            self.tts_engine.say("Audio system initialized. Testing Bluetooth output.")
            self.tts_engine.runAndWait()
            
            self.tts_queue = queue.Queue()
            self.tts_thread = threading.Thread(
                target=self.process_tts_queue, 
                daemon=True
            )
            self.tts_thread.start()
            self.logger.info("Audio system initialized")
            print("Audio system ready - you should have heard a test message")
            
            # Print current audio settings
            print("\nCurrent audio settings:")
            print(f"Rate: {self.tts_engine.getProperty('rate')}")
            print(f"Volume: {self.tts_engine.getProperty('volume')}")
            print(f"Voice: {self.tts_engine.getProperty('voice')}")
            
        except Exception as e:
            self.logger.error(f"Failed to initialize audio: {e}")
            print("WARNING: Audio system failed to initialize - no speech output available")
            print(f"Error details: {str(e)}")
            self.config['greeting']['enabled'] = False
    
    def setup_face_recognition(self):
        """Initialize face detection and recognition components"""
        self.known_face_encodings = []
        self.known_face_names = []
        self.load_known_faces()
    
    def setup_encryption(self):
        """Configure face data encryption if enabled"""
        if self.config['security']['encrypt_faces']:
            try:
                key_file = self.base_dir / 'encryption.key'
                if key_file.exists():
                    with open(key_file, 'rb') as f:
                        key = f.read()
                else:
                    key = Fernet.generate_key()
                    with open(key_file, 'wb') as f:
                        f.write(key)
                self.cipher = Fernet(key)
                self.logger.info("Encryption initialized")
            except Exception as e:
                self.logger.error(f"Failed to initialize encryption: {e}")
                self.config['security']['encrypt_faces'] = False
    
    def setup_signal_handlers(self):
        """Set up signal handlers for graceful shutdown"""
        signal.signal(signal.SIGINT, self.signal_handler)
        signal.signal(signal.SIGTERM, self.signal_handler)
    
    def signal_handler(self, signum, frame):
        """Handle shutdown signals"""
        self.logger.info("Shutdown signal received")
        self.running = False
    
    def load_known_faces(self):
        """Load known faces from storage"""
        self.logger.info("Loading known faces...")
        try:
            for face_file in self.known_faces_dir.glob('*.*'):
                if face_file.suffix.lower() in ('.png', '.jpg', '.jpeg'):
                    name = face_file.stem
                    self.logger.debug(f"Loading face for: {name}")
                    
                    # Load and process face
                    image = face_recognition.load_image_file(str(face_file))
                    encodings = face_recognition.face_encodings(image)
                    
                    if encodings:
                        face_encoding = encodings[0]
                        if self.config['security']['encrypt_faces']:
                            face_encoding = self.encrypt_encoding(face_encoding)
                        self.known_face_encodings.append(face_encoding)
                        self.known_face_names.append(name)
                        self.logger.debug(f"Successfully loaded face for: {name}")
                    else:
                        self.logger.warning(f"No face found in {face_file}")
            
            self.logger.info(f"Loaded {len(self.known_face_names)} known faces")
        except Exception as e:
            self.logger.error(f"Error loading known faces: {e}")
    
    def process_tts_queue(self):
        """Process text-to-speech queue"""
        while True:
            try:
                message = self.tts_queue.get(timeout=1)
                if message and hasattr(self, 'tts_engine'):
                    # Ensure we're at full volume for each message
                    self.tts_engine.setProperty('volume', 1.0)
                    self.tts_engine.say(message)
                    self.tts_engine.runAndWait()
                self.tts_queue.task_done()
            except queue.Empty:
                continue
            except Exception as e:
                self.logger.error(f"TTS Error: {e}")
                print(f"Speech failed: {str(e)}")
    
    def speak_async(self, message):
        """Add message to TTS queue"""
        try:
            if hasattr(self, 'tts_queue'):
                self.tts_queue.put(message)
                print(f"Speaking: {message}")
        except Exception as e:
            self.logger.error(f"Failed to queue speech: {e}")
            print(f"Speech error: {str(e)}")
    
    def get_frame(self):
        """Get frame from camera with error recovery"""
        if not hasattr(self, 'camera') or not self.camera.isOpened():
            self.logger.error("Camera not initialized or closed")
            return False, None
            
        for _ in range(3):  # Try up to 3 times
            ret, frame = self.camera.read()
            if ret and frame is not None:
                return True, frame
            self.logger.warning("Failed to capture frame, retrying...")
            time.sleep(0.1)  # Short delay between retries
            
        # If we get here, all retries failed
        self.logger.error("Failed to capture frame after 3 attempts")
        return False, None
    
    def process_frame(self, frame):
        """Process a single frame"""
        # Convert frame to RGB
        rgb_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        
        # Find faces in frame
        locations = face_recognition.face_locations(
            rgb_frame,
            model=self.config['recognition']['model']
        )
        
        if not locations:
            return frame
        
        # Get face encodings
        encodings = face_recognition.face_encodings(
            rgb_frame,
            locations,
            num_jitters=1  # Increase for better accuracy, but slower
        )
        
        # Process each face
        for encoding, location in zip(encodings, locations):
            name = self.identify_face(encoding)
            self.handle_face(name, encoding, location, frame)
        
        return frame
    
    def identify_face(self, face_encoding):
        """Identify a face encoding"""
        if not self.known_face_encodings:
            return "Unknown"
        
        if self.config['security']['encrypt_faces']:
            face_encoding = self.encrypt_encoding(face_encoding)
        
        matches = face_recognition.compare_faces(
            self.known_face_encodings,
            face_encoding,
            tolerance=self.config['recognition']['tolerance']
        )
        
        if True in matches:
            face_distances = face_recognition.face_distance(
                self.known_face_encodings,
                face_encoding
            )
            best_match_index = np.argmin(face_distances)
            if matches[best_match_index]:
                return self.known_face_names[best_match_index]
        
        return "Unknown"
    
    def handle_face(self, name, face_encoding, face_location, frame):
        """Handle detected face"""
        # Draw rectangle and name
        top, right, bottom, left = face_location
        color = (0, 255, 0) if name != "Unknown" else (0, 0, 255)
        
        cv2.rectangle(frame, (left, top), (right, bottom), color, 2)
        cv2.rectangle(frame, (left, bottom - 35), (right, bottom), color, cv2.FILLED)
        cv2.putText(frame, name, (left + 6, bottom - 6),
                   cv2.FONT_HERSHEY_DUPLEX, 0.6, (255, 255, 255), 1)
        
        # Handle greeting
        if name != "Unknown":
            self.handle_known_face(name)
        else:
            self.handle_unknown_face(face_encoding, face_location, frame)
    
    def handle_known_face(self, name):
        """Handle known face detection"""
        current_time = time.time()
        last_greeting = self.last_greeting_time.get(name, 0)
        
        # Always print when we see a known face
        print(f"\nRecognized: {name}")
        
        if current_time - last_greeting > self.config['greeting']['cooldown']:
            self.last_greeting_time[name] = current_time
            
            # Get custom greeting if available
            greeting = self.config['greeting']['custom_greetings'].get(
                name,
                f"Hello {name}!"
            )
            
            self.logger.info(f"Greeting {name}")
            # Print greeting to terminal
            print(f"{greeting}")
            
            # Audio greeting if enabled
            if self.config['greeting']['enabled']:
                self.speak_async(greeting)
    
    def handle_unknown_face(self, face_encoding, face_location, frame):
        """Handle unknown face detection"""
        # Always print when we see an unknown face
        print("\nUnknown face detected!")
        
        face_key = str(face_location)
        if face_key not in self.unknown_face_counters:
            self.unknown_face_counters[face_key] = 0
            print("Starting face capture sequence...")
        
        self.unknown_face_counters[face_key] += 1
        print(f"Capture progress: {self.unknown_face_counters[face_key]}/5 frames")
        
        # Save unknown face after seeing it a few times (to ensure good quality)
        if self.unknown_face_counters[face_key] >= 5:  # 5 frames for quick capture
            if face_key not in self.unknown_face_counters or self.unknown_face_counters[face_key] != -1000:  # Check if not already saved
                face_id = self.save_unknown_face(frame, face_location, face_encoding)
                if face_id:
                    print(f"\nSaved new face as ID: {face_id}")
                    print(f"Photo saved to: data/unknown_faces/unknown_*_{face_id}.jpg")
                    print("To name this person:")
                    print(f"1. Copy their photo: cp data/unknown_faces/unknown_*_{face_id}.jpg data/known_faces/PersonName.jpg")
                    print("2. Press 'r' to reload known faces")
                    # Announce new face saved
                    if self.config['greeting']['enabled']:
                        self.speak_async("New face detected and saved")
                self.unknown_face_counters[face_key] = -1000  # Mark as saved
    
    def save_unknown_face(self, frame, face_location, face_encoding):
        """Save unknown face and return face_id"""
        try:
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            face_id = str(uuid.uuid4())[:8]
            filename = f"unknown_{timestamp}_{face_id}.jpg"
            
            # Extract and save face image
            top, right, bottom, left = face_location
            # Add padding around the face
            padding = 50
            height, width = frame.shape[:2]
            top = max(0, top - padding)
            bottom = min(height, bottom + padding)
            left = max(0, left - padding)
            right = min(width, right + padding)
            
            face_image = frame[top:bottom, left:right]
            face_path = self.unknown_faces_dir / filename
            cv2.imwrite(str(face_path), face_image)
            
            # Save metadata
            metadata = {
                "timestamp": datetime.now().isoformat(),
                "face_id": face_id,
                "filename": filename,
                "encoding": face_encoding.tolist() if not self.config['security']['encrypt_faces']
                          else self.encrypt_encoding(face_encoding).tolist()
            }
            
            metadata_file = self.unknown_faces_dir / f"{face_id}_meta.json"
            with open(metadata_file, 'w') as f:
                json.dump(metadata, f)
            
            self.logger.info(f"Saved unknown face: {face_id}")
            return face_id
            
        except Exception as e:
            self.logger.error(f"Error saving unknown face: {e}")
            return None
    
    def encrypt_encoding(self, encoding):
        """Encrypt face encoding"""
        if not self.config['security']['encrypt_faces']:
            return encoding
        try:
            data = json.dumps(encoding.tolist()).encode()
            return np.array(json.loads(
                self.cipher.encrypt(data).decode()
            ))
        except Exception as e:
            self.logger.error(f"Encryption error: {e}")
            return encoding
    
    def update_performance_stats(self):
        """Update performance statistics"""
        if len(self.frame_times) > 30:
            self.frame_times.pop(0)
        
        if self.frame_times:
            fps = len(self.frame_times) / (self.frame_times[-1] - self.frame_times[0])
            cpu_percent = psutil.cpu_percent()
            memory = psutil.Process().memory_info().rss / 1024 / 1024  # MB
            
            return f"FPS: {fps:.1f} | CPU: {cpu_percent}% | Memory: {memory:.1f}MB"
        return ""
    
    def cleanup(self):
        """Clean up resources"""
        self.logger.info("Cleaning up...")
        self.camera.release()
        cv2.destroyAllWindows()
        
        if self.config['greeting']['enabled']:
            self.tts_queue.join()
    
    def run(self):
        """Main recognition loop"""
        self.logger.info("Starting facial recognition system...")
        print("\nFacial Recognition System Running")
        print("=================================")
        print("Controls:")
        print("  'q' - Quit")
        print("  'r' - Reload known faces")
        print("  's' - Toggle performance stats")
        print("  'v' - Toggle voice output")
        print("\nFace Management:")
        print("- Known faces are loaded from: data/known_faces/")
        print("- Unknown faces are saved to: data/unknown_faces/")
        print("- To name someone:")
        print("  1. Copy their photo from unknown_faces to known_faces")
        print("  2. Rename it to their name (e.g., John.jpg)")
        print("  3. Press 'r' to reload\n")
        
        # Test audio at startup
        if self.config['greeting']['enabled']:
            self.speak_async("System ready")
        
        if self.known_face_names:
            print("Currently known people:", ", ".join(self.known_face_names))
        print("\nWaiting for faces...")
        
        while self.running:
            try:
                # Capture frame
                ret, frame = self.get_frame()
                if not ret:
                    continue
                
                # Process frame
                frame = self.process_frame(frame)
                
                # Update performance stats
                if self.show_stats:
                    self.frame_times.append(time.time())
                    stats = self.update_performance_stats()
                    cv2.putText(frame, stats, (10, 30),
                              cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 0), 2)
                
                # Display frame
                cv2.imshow('Facial Recognition System', frame)
                
                # Handle key presses
                key = cv2.waitKey(1) & 0xFF
                if key == ord('q'):
                    print("\nShutting down...")
                    self.running = False
                elif key == ord('r'):
                    print("\nReloading known faces...")
                    self.load_known_faces()
                    print(f"Loaded {len(self.known_face_names)} known faces")
                    if self.known_face_names:
                        print("Known people:", ", ".join(self.known_face_names))
                    print("\nWaiting for faces...")
                elif key == ord('s'):
                    self.show_stats = not self.show_stats
                elif key == ord('v'):
                    self.config['greeting']['enabled'] = not self.config['greeting']['enabled']
                    status = "enabled" if self.config['greeting']['enabled'] else "disabled"
                    print(f"\nVoice output {status}")
                    if self.config['greeting']['enabled']:
                        self.speak_async("Voice output enabled")
                
            except Exception as e:
                self.logger.error(f"Error in main loop: {e}")
                if not self.running:
                    break
                time.sleep(1)
        
        self.cleanup()
        print("\nSystem shutdown complete")

def main():
    """Main entry point"""
    try:
        system = FacialRecognitionSystem()
        system.run()
    except Exception as e:
        logging.error(f"Fatal error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main() 