#!/usr/bin/env python3
"""
Face Management Module for Raspberry Pi Facial Recognition System
Implements face database operations, validation, and maintenance functions
"""

import os
import sys
import json
import shutil
import yaml
import face_recognition
import cv2
import click
import logging
from datetime import datetime, timedelta
from pathlib import Path
from PIL import Image
from logging.handlers import RotatingFileHandler

class FaceManager:
    def __init__(self):
        """Initialize face management system"""
        self.setup_logging()
        self.load_config()
        self.setup_paths()
    
    def setup_logging(self):
        """Set up logging configuration"""
        self.logger = logging.getLogger('FaceManager')
        self.logger.setLevel(logging.INFO)
        
        # File handler
        log_file = '/var/log/facial-recognition/manager.log'
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
        """Load configuration from YAML file"""
        try:
            with open('config.yml', 'r') as f:
                self.config = yaml.safe_load(f)
        except Exception as e:
            self.logger.error(f"Failed to load config: {e}")
            sys.exit(1)
    
    def setup_paths(self):
        """Set up storage paths"""
        storage_config = self.config['storage']
        self.base_dir = Path(storage_config['base_dir'])
        self.known_faces_dir = Path(storage_config['known_faces_dir'])
        self.unknown_faces_dir = Path(storage_config['unknown_faces_dir'])
        self.logs_dir = Path(storage_config['logs_dir'])
        
        # Create directories if they don't exist
        for directory in [self.known_faces_dir, self.unknown_faces_dir, self.logs_dir]:
            directory.mkdir(parents=True, exist_ok=True)
    
    def validate_image(self, image_path):
        """
        Validate image file and perform face detection
        
        Parameters:
            image_path (str): Path to image file
            
        Returns:
            bool: True if image contains exactly one valid face
        """
        try:
            # Check if file exists and is an image
            if not os.path.exists(image_path):
                raise ValueError("Image file does not exist")
            
            # Try to open with PIL to validate image
            try:
                with Image.open(image_path) as img:
                    img.verify()
            except Exception:
                raise ValueError("Invalid image file")
            
            # Load image and check for faces
            image = face_recognition.load_image_file(image_path)
            face_locations = face_recognition.face_locations(image)
            
            if not face_locations:
                raise ValueError("No face detected in image")
            
            if len(face_locations) > 1:
                raise ValueError("Multiple faces detected in image")
            
            # Check image quality
            gray = cv2.cvtColor(image, cv2.COLOR_RGB2GRAY)
            blur_value = cv2.Laplacian(gray, cv2.CV_64F).var()
            
            if blur_value < self.config['recognition']['blur_threshold']:
                raise ValueError("Image is too blurry")
            
            return True
        
        except Exception as e:
            self.logger.error(f"Image validation failed: {e}")
            return False
    
    def add_face(self, name, image_path):
        """
        Register new face in the database
        
        Parameters:
            name (str): Identifier for the face
            image_path (str): Path to face image
            
        Returns:
            bool: True if registration successful
        """
        try:
            # Validate name
            name = self.sanitize_name(name)
            if not name:
                raise ValueError("Invalid name")
            
            # Check if name already exists
            existing_faces = [f.stem for f in self.known_faces_dir.glob('*.*')]
            if name in existing_faces:
                raise ValueError(f"Face with name '{name}' already exists")
            
            # Validate image
            if not self.validate_image(image_path):
                raise ValueError("Image validation failed")
            
            # Copy image to known faces directory
            file_ext = os.path.splitext(image_path)[1].lower()
            new_path = self.known_faces_dir / f"{name}{file_ext}"
            shutil.copy2(image_path, new_path)
            
            self.logger.info(f"Successfully added face for {name}")
            return True
            
        except Exception as e:
            self.logger.error(f"Error adding face: {e}")
            return False
    
    def remove_face(self, name):
        """
        Remove face registration from database
        
        Parameters:
            name (str): Face identifier to remove
            
        Returns:
            bool: True if removal successful
        """
        try:
            name = self.sanitize_name(name)
            found = False
            
            for face_file in self.known_faces_dir.glob('*.*'):
                if face_file.stem == name:
                    face_file.unlink()
                    found = True
                    self.logger.info(f"Removed face: {name}")
                    break
            
            if not found:
                raise ValueError(f"Face '{name}' not found")
            
            return True
            
        except Exception as e:
            self.logger.error(f"Error removing face: {e}")
            return False
    
    def list_known_faces(self):
        """
        Enumerate registered faces in database
        
        Returns:
            list: List of dictionaries containing face data
        """
        try:
            faces = []
            for face_file in sorted(self.known_faces_dir.glob('*.*')):
                if face_file.suffix.lower() in ('.png', '.jpg', '.jpeg'):
                    faces.append({
                        'name': face_file.stem,
                        'file': face_file.name,
                        'added': datetime.fromtimestamp(face_file.stat().st_mtime)
                    })
            return faces
        except Exception as e:
            self.logger.error(f"Error listing known faces: {e}")
            return []
    
    def list_unknown_faces(self):
        """
        Enumerate unidentified faces in database
        
        Returns:
            list: List of dictionaries containing face data
        """
        try:
            faces = []
            for face_file in sorted(self.unknown_faces_dir.glob('unknown_*.jpg')):
                meta_file = self.unknown_faces_dir / f"{face_file.stem}_meta.json"
                if meta_file.exists():
                    with open(meta_file, 'r') as f:
                        metadata = json.load(f)
                    faces.append({
                        'id': metadata['face_id'],
                        'file': face_file.name,
                        'timestamp': datetime.fromisoformat(metadata['timestamp'])
                    })
            return faces
        except Exception as e:
            self.logger.error(f"Error listing unknown faces: {e}")
            return []
    
    def promote_unknown_face(self, face_id, new_name):
        """
        Register unknown face as known face
        
        Parameters:
            face_id (str): ID of unknown face
            new_name (str): Name for registration
            
        Returns:
            bool: True if promotion successful
        """
        try:
            new_name = self.sanitize_name(new_name)
            if not new_name:
                raise ValueError("Invalid name")
            
            # Find unknown face files
            face_file = None
            meta_file = None
            for f in self.unknown_faces_dir.glob(f"*{face_id}*.jpg"):
                face_file = f
                meta_file = self.unknown_faces_dir / f"{f.stem}_meta.json"
                break
            
            if not face_file or not meta_file.exists():
                raise ValueError(f"Unknown face {face_id} not found")
            
            # Validate face image
            if not self.validate_image(str(face_file)):
                raise ValueError("Face image validation failed")
            
            # Copy to known faces
            new_path = self.known_faces_dir / f"{new_name}.jpg"
            shutil.copy2(face_file, new_path)
            
            # Update metadata
            with open(meta_file, 'r') as f:
                metadata = json.load(f)
            metadata['promoted'] = {
                'timestamp': datetime.now().isoformat(),
                'new_name': new_name
            }
            with open(meta_file, 'w') as f:
                json.dump(metadata, f, indent=2)
            
            self.logger.info(f"Promoted {face_id} to {new_name}")
            return True
            
        except Exception as e:
            self.logger.error(f"Error promoting face: {e}")
            return False
    
    def clean_unknown_faces(self, days_old=30):
        """
        Remove old unidentified faces from database
        
        Parameters:
            days_old (int): Age threshold in days
            
        Returns:
            int: Number of faces removed
        """
        try:
            cutoff_date = datetime.now() - timedelta(days=days_old)
            cleaned_count = 0
            
            for face_file in self.unknown_faces_dir.glob('unknown_*.jpg'):
                meta_file = self.unknown_faces_dir / f"{face_file.stem}_meta.json"
                
                if meta_file.exists():
                    with open(meta_file, 'r') as f:
                        metadata = json.load(f)
                    
                    timestamp = datetime.fromisoformat(metadata['timestamp'])
                    if timestamp < cutoff_date:
                        face_file.unlink()
                        meta_file.unlink()
                        cleaned_count += 1
                else:
                    # If no metadata, use file timestamp
                    if datetime.fromtimestamp(face_file.stat().st_mtime) < cutoff_date:
                        face_file.unlink()
                        cleaned_count += 1
            
            self.logger.info(f"Cleaned {cleaned_count} old unknown faces")
            return cleaned_count
            
        except Exception as e:
            self.logger.error(f"Error cleaning unknown faces: {e}")
            return 0
    
    def backup_faces(self):
        """
        Create backup of face database
        
        Returns:
            bool: True if backup successful
        """
        try:
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            backup_dir = self.base_dir / 'backups' / timestamp
            backup_dir.mkdir(parents=True, exist_ok=True)
            
            # Backup known faces
            known_backup = backup_dir / 'known_faces'
            shutil.copytree(self.known_faces_dir, known_backup)
            
            # Backup unknown faces
            unknown_backup = backup_dir / 'unknown_faces'
            shutil.copytree(self.unknown_faces_dir, unknown_backup)
            
            # Create backup info
            backup_info = {
                'timestamp': timestamp,
                'known_faces': len(list(known_backup.glob('*.*'))),
                'unknown_faces': len(list(unknown_backup.glob('*.*')))
            }
            
            with open(backup_dir / 'backup_info.json', 'w') as f:
                json.dump(backup_info, f, indent=2)
            
            self.logger.info(f"Backup created: {timestamp}")
            return True
            
        except Exception as e:
            self.logger.error(f"Error creating backup: {e}")
            return False
    
    @staticmethod
    def sanitize_name(name):
        """
        Sanitize name string for filesystem compatibility
        
        Parameters:
            name (str): Input name string
            
        Returns:
            str: Sanitized name string
        """
        # Remove special characters and extra spaces
        name = ''.join(c for c in name if c.isalnum() or c in (' ', '-', '_'))
        name = ' '.join(name.split())  # Normalize spaces
        return name.strip()

@click.group()
def cli():
    """Facial Recognition System - Face Management Tool"""
    pass

@cli.command()
@click.argument('name')
@click.argument('image_path')
def add(name, image_path):
    """Add a new known face"""
    manager = FaceManager()
    if manager.add_face(name, image_path):
        click.echo(f"Successfully added face for {name}")
    else:
        click.echo("Failed to add face")
        sys.exit(1)

@cli.command()
@click.argument('name')
def remove(name):
    """Remove a known face"""
    manager = FaceManager()
    if manager.remove_face(name):
        click.echo(f"Successfully removed face: {name}")
    else:
        click.echo("Failed to remove face")
        sys.exit(1)

@cli.command()
def list_known():
    """List all known faces"""
    manager = FaceManager()
    faces = manager.list_known_faces()
    
    if not faces:
        click.echo("No known faces found")
        return
    
    click.echo("\nKnown Faces:")
    for face in faces:
        click.echo(f"- {face['name']} (Added: {face['added'].strftime('%Y-%m-%d %H:%M:%S')})")

@cli.command()
def list_unknown():
    """List all unknown faces"""
    manager = FaceManager()
    faces = manager.list_unknown_faces()
    
    if not faces:
        click.echo("No unknown faces found")
        return
    
    click.echo("\nUnknown Faces:")
    for face in faces:
        click.echo(f"- ID: {face['id']} (Detected: {face['timestamp'].strftime('%Y-%m-%d %H:%M:%S')})")

@cli.command()
@click.argument('face_id')
@click.argument('new_name')
def promote(face_id, new_name):
    """Promote an unknown face to known face"""
    manager = FaceManager()
    if manager.promote_unknown_face(face_id, new_name):
        click.echo(f"Successfully promoted {face_id} to {new_name}")
    else:
        click.echo("Failed to promote face")
        sys.exit(1)

@cli.command()
@click.option('--days', default=30, help='Remove faces older than this many days')
def clean(days):
    """Clean up old unknown faces"""
    manager = FaceManager()
    count = manager.clean_unknown_faces(days)
    click.echo(f"Cleaned {count} old unknown faces")

@cli.command()
def backup():
    """Create a backup of all face data"""
    manager = FaceManager()
    if manager.backup_faces():
        click.echo("Backup created successfully")
    else:
        click.echo("Failed to create backup")
        sys.exit(1)

if __name__ == "__main__":
    cli() 