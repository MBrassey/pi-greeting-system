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
import face_recognition  # Import the module directly

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
        """Initialize camera with support for both USB webcam and Arducam IMX519"""
        self.using_picamera = self.config['camera']['type'] == 'picamera'
        
        if self.using_picamera:
            try:
                self.logger.info("Initializing Picamera2 for Arducam IMX519...")
                self.camera = Picamera2()
                
                # Configure camera for IMX519
                sensor_mode = self.config['camera']['sensor_mode']
                resolution = self.config['recognition']['resolution']
                
                # Create a camera configuration
                config = self.camera.create_still_configuration(
                    main={"size": resolution},
                    raw={"size": resolution},
                    controls={
                        "FrameDurationLimits": (33333, 33333),  # For 30fps
                        "AnalogueGain": 1.0,
                        "ColourGains": (1.0, 1.0),
                        "AeEnable": True,
                        "AwbEnable": True,
                        "NoiseReductionMode": controls.draft.NoiseReductionModeEnum.HighQuality
                    }
                )
                
                # Apply configuration
                self.camera.configure(config)
                
                # Set additional camera properties
                self.camera.set_controls({
                    "Brightness": self.config['camera']['brightness'] / 100.0,
                    "Contrast": self.config['camera']['contrast'] / 100.0,
                })
                
                # Start the camera
                self.camera.start()
                time.sleep(2)  # Allow camera to warm up
                
                self.logger.info("Picamera2 initialized successfully")
                
            except Exception as e:
                self.logger.error(f"Failed to initialize Picamera2: {e}")
                self.logger.warning("Falling back to USB camera...")
                self.using_picamera = False
        
        if not self.using_picamera:
            # Try both video0 and video1 for USB webcam
            usb_devices = ['/dev/video0', '/dev/video1']
            
            for device in usb_devices:
                try:
                    self.logger.info(f"Trying USB camera device: {device}")
                    self.camera = cv2.VideoCapture(device)
                    if self.camera.isOpened():
                        # Test frame capture
                        ret, frame = self.camera.read()
                        if ret and frame is not None:
                            self.logger.info(f"Successfully opened camera on {device}")
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
                            self.logger.warning(f"Could not read frame from {device}")
                            self.camera.release()
                    else:
                        self.logger.warning(f"Could not open {device}")
                except Exception as e:
                    self.logger.error(f"Error trying {device}: {str(e)}")
                    if hasattr(self, 'camera'):
                        self.camera.release()
            
            # If we get here, no camera worked
            self.logger.error("Could not initialize any camera!")
            self.logger.error("Available devices:")
            os.system("ls -l /dev/video*")
            sys.exit(1)
    
    def setup_audio(self):
        """Initialize text-to-speech synthesis engine"""
        if self.config['greeting']['enabled']:
            try:
                self.tts_engine = pyttsx3.init()
                self.tts_engine.setProperty('rate', self.config['greeting']['rate'])
                self.tts_engine.setProperty('volume', self.config['greeting']['volume'])
                self.tts_queue = queue.Queue()
                self.tts_thread = threading.Thread(
                    target=self.process_tts_queue, 
                    daemon=True
                )
                self.tts_thread.start()
                self.logger.info("Audio system initialized")
            except Exception as e:
                self.logger.error(f"Failed to initialize audio: {e}")
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
                if message and self.config['greeting']['enabled']:
                    self.tts_engine.say(message)
                    self.tts_engine.runAndWait()
                self.tts_queue.task_done()
            except queue.Empty:
                continue
            except Exception as e:
                self.logger.error(f"TTS Error: {e}")
    
    def speak_async(self, message):
        """Add message to TTS queue"""
        if self.config['greeting']['enabled']:
            self.tts_queue.put(message)
    
    def get_frame(self):
        """Get frame from camera with error recovery"""
        if self.using_picamera:
            try:
                # Capture frame from Picamera2
                frame = self.camera.capture_array()
                if frame is not None:
                    # Convert frame to RGB format
                    frame = cv2.cvtColor(frame, cv2.COLOR_RGB2BGR)
                    return True, frame
            except Exception as e:
                self.logger.error(f"Picamera2 capture error: {e}")
                return False, None
        else:
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
        rgb_frame = frame if self.using_picamera else cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        
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
        
        if current_time - last_greeting > self.config['greeting']['cooldown']:
            self.last_greeting_time[name] = current_time
            
            # Get custom greeting if available
            greeting = self.config['greeting']['custom_greetings'].get(
                name,
                f"Hello {name}!"
            )
            
            self.logger.info(f"Greeting {name}")
            self.speak_async(greeting)
    
    def handle_unknown_face(self, face_encoding, face_location, frame):
        """Handle unknown face detection"""
        if not self.config['storage']['auto_clean']:
            return
        
        face_key = str(face_location)
        if face_key not in self.unknown_face_counters:
            self.unknown_face_counters[face_key] = 0
        
        self.unknown_face_counters[face_key] += 1
        
        # Save unknown face after threshold
        if self.unknown_face_counters[face_key] >= 10:
            self.save_unknown_face(frame, face_location, face_encoding)
            self.unknown_face_counters[face_key] = -1000  # Prevent multiple saves
    
    def save_unknown_face(self, frame, face_location, face_encoding):
        """Save unknown face"""
        try:
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            face_id = str(uuid.uuid4())[:8]
            filename = f"unknown_{timestamp}_{face_id}.jpg"
            
            # Extract and save face image
            top, right, bottom, left = face_location
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
            
        except Exception as e:
            self.logger.error(f"Error saving unknown face: {e}")
    
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
        if self.using_picamera:
            self.camera.stop()
        else:
            self.camera.release()
        cv2.destroyAllWindows()
        
        if self.config['greeting']['enabled']:
            self.tts_queue.join()
    
    def run(self):
        """Main recognition loop"""
        self.logger.info("Starting facial recognition system...")
        self.logger.info("Press 'q' to quit, 'r' to reload faces, 's' to toggle stats")
        
        while self.running:
            try:
                # Capture frame
                ret, frame = self.get_frame()
                if not ret:
                    self.logger.error("Failed to capture frame")
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
                    self.running = False
                elif key == ord('r'):
                    self.logger.info("Reloading known faces...")
                    self.load_known_faces()
                elif key == ord('s'):
                    self.show_stats = not self.show_stats
                elif key == ord('c'):
                    # Capture current frame
                    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                    cv2.imwrite(f"capture_{timestamp}.jpg", frame)
                    self.logger.info(f"Frame captured: capture_{timestamp}.jpg")
                
            except Exception as e:
                self.logger.error(f"Error in main loop: {e}")
                if not self.running:
                    break
                time.sleep(1)  # Prevent rapid error loops
        
        self.cleanup()
        self.logger.info("System shutdown complete")

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