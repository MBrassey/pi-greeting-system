#!/usr/bin/env python3
"""
Web Interface for Raspberry Pi Facial Recognition System
Provides a web-based interface for managing faces and system settings
"""

import os
import yaml
import json
import logging
from datetime import datetime
from pathlib import Path
from flask import Flask, render_template, request, redirect, url_for, flash, jsonify, send_file
from flask_login import LoginManager, UserMixin, login_user, login_required, logout_user, current_user
from werkzeug.security import generate_password_hash, check_password_hash
from werkzeug.utils import secure_filename
from logging.handlers import RotatingFileHandler

# Initialize Flask app
app = Flask(__name__)
app.config['SECRET_KEY'] = os.urandom(24)
app.config['UPLOAD_FOLDER'] = 'uploads'
app.config['MAX_CONTENT_LENGTH'] = 16 * 1024 * 1024  # 16MB max file size

# Initialize login manager
login_manager = LoginManager()
login_manager.init_app(app)
login_manager.login_view = 'login'

# User class for authentication
class User(UserMixin):
    def __init__(self, user_id):
        self.id = user_id

# Load configuration
def load_config():
    with open('config.yml', 'r') as f:
        return yaml.safe_load(f)

config = load_config()

# Setup logging
logger = logging.getLogger('WebInterface')
logger.setLevel(logging.INFO)
handler = RotatingFileHandler(
    '/var/log/facial-recognition/web.log',
    maxBytes=10485760,
    backupCount=5
)
handler.setFormatter(logging.Formatter(
    '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
))
logger.addHandler(handler)

# Ensure upload directory exists
os.makedirs(app.config['UPLOAD_FOLDER'], exist_ok=True)

@login_manager.user_loader
def load_user(user_id):
    if user_id == config['web_interface']['username']:
        return User(user_id)
    return None

@app.route('/')
@login_required
def index():
    """Dashboard page"""
    stats = get_system_stats()
    return render_template('dashboard.html', stats=stats)

@app.route('/login', methods=['GET', 'POST'])
def login():
    """Login page"""
    if request.method == 'POST':
        username = request.form.get('username')
        password = request.form.get('password')
        
        if (username == config['web_interface']['username'] and
            check_password_hash(config['web_interface']['password_hash'], password)):
            login_user(User(username))
            flash('Logged in successfully.', 'success')
            return redirect(url_for('index'))
        
        flash('Invalid username or password.', 'error')
    
    return render_template('login.html')

@app.route('/logout')
@login_required
def logout():
    """Logout route"""
    logout_user()
    flash('Logged out successfully.', 'success')
    return redirect(url_for('login'))

@app.route('/known-faces')
@login_required
def known_faces():
    """Known faces management page"""
    faces = list_known_faces()
    return render_template('known_faces.html', faces=faces)

@app.route('/unknown-faces')
@login_required
def unknown_faces():
    """Unknown faces management page"""
    faces = list_unknown_faces()
    return render_template('unknown_faces.html', faces=faces)

@app.route('/settings')
@login_required
def settings():
    """Settings page"""
    return render_template('settings.html', config=config)

@app.route('/api/faces/known', methods=['GET'])
@login_required
def api_known_faces():
    """API endpoint for known faces"""
    faces = list_known_faces()
    return jsonify(faces)

@app.route('/api/faces/unknown', methods=['GET'])
@login_required
def api_unknown_faces():
    """API endpoint for unknown faces"""
    faces = list_unknown_faces()
    return jsonify(faces)

@app.route('/api/faces/add', methods=['POST'])
@login_required
def api_add_face():
    """API endpoint to add a new face"""
    try:
        if 'image' not in request.files:
            return jsonify({'error': 'No image file'}), 400
        
        image = request.files['image']
        name = request.form.get('name')
        
        if not name:
            return jsonify({'error': 'No name provided'}), 400
        
        if image.filename == '':
            return jsonify({'error': 'No selected file'}), 400
        
        if not allowed_file(image.filename):
            return jsonify({'error': 'Invalid file type'}), 400
        
        # Save uploaded file
        filename = secure_filename(image.filename)
        filepath = os.path.join(app.config['UPLOAD_FOLDER'], filename)
        image.save(filepath)
        
        # Add face
        success = add_face(name, filepath)
        
        # Clean up upload
        os.remove(filepath)
        
        if success:
            return jsonify({'message': 'Face added successfully'})
        else:
            return jsonify({'error': 'Failed to add face'}), 500
            
    except Exception as e:
        logger.error(f"Error adding face: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/faces/remove', methods=['POST'])
@login_required
def api_remove_face():
    """API endpoint to remove a face"""
    try:
        name = request.json.get('name')
        if not name:
            return jsonify({'error': 'No name provided'}), 400
        
        if remove_face(name):
            return jsonify({'message': 'Face removed successfully'})
        else:
            return jsonify({'error': 'Failed to remove face'}), 500
            
    except Exception as e:
        logger.error(f"Error removing face: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/faces/promote', methods=['POST'])
@login_required
def api_promote_face():
    """API endpoint to promote unknown face"""
    try:
        face_id = request.json.get('face_id')
        new_name = request.json.get('new_name')
        
        if not face_id or not new_name:
            return jsonify({'error': 'Missing required parameters'}), 400
        
        if promote_unknown_face(face_id, new_name):
            return jsonify({'message': 'Face promoted successfully'})
        else:
            return jsonify({'error': 'Failed to promote face'}), 500
            
    except Exception as e:
        logger.error(f"Error promoting face: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/settings', methods=['POST'])
@login_required
def api_update_settings():
    """API endpoint to update settings"""
    try:
        new_settings = request.json
        if update_settings(new_settings):
            return jsonify({'message': 'Settings updated successfully'})
        else:
            return jsonify({'error': 'Failed to update settings'}), 500
            
    except Exception as e:
        logger.error(f"Error updating settings: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/system/stats', methods=['GET'])
@login_required
def api_system_stats():
    """API endpoint for system statistics"""
    return jsonify(get_system_stats())

def allowed_file(filename):
    """Check if file type is allowed"""
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in {'png', 'jpg', 'jpeg'}

def list_known_faces():
    """List all known faces"""
    faces = []
    known_faces_dir = Path(config['storage']['known_faces_dir'])
    
    for face_file in sorted(known_faces_dir.glob('*.*')):
        if face_file.suffix.lower() in ('.png', '.jpg', '.jpeg'):
            faces.append({
                'name': face_file.stem,
                'file': face_file.name,
                'added': datetime.fromtimestamp(face_file.stat().st_mtime).isoformat()
            })
    
    return faces

def list_unknown_faces():
    """List all unknown faces"""
    faces = []
    unknown_faces_dir = Path(config['storage']['unknown_faces_dir'])
    
    for face_file in sorted(unknown_faces_dir.glob('unknown_*.jpg')):
        meta_file = unknown_faces_dir / f"{face_file.stem}_meta.json"
        if meta_file.exists():
            with open(meta_file, 'r') as f:
                metadata = json.load(f)
            faces.append({
                'id': metadata['face_id'],
                'file': face_file.name,
                'timestamp': metadata['timestamp']
            })
    
    return faces

def add_face(name, image_path):
    """Add a new known face"""
    try:
        from manage_faces import FaceManager
        manager = FaceManager()
        return manager.add_face(name, image_path)
    except Exception as e:
        logger.error(f"Error adding face: {e}")
        return False

def remove_face(name):
    """Remove a known face"""
    try:
        from manage_faces import FaceManager
        manager = FaceManager()
        return manager.remove_face(name)
    except Exception as e:
        logger.error(f"Error removing face: {e}")
        return False

def promote_unknown_face(face_id, new_name):
    """Promote unknown face to known face"""
    try:
        from manage_faces import FaceManager
        manager = FaceManager()
        return manager.promote_unknown_face(face_id, new_name)
    except Exception as e:
        logger.error(f"Error promoting face: {e}")
        return False

def update_settings(new_settings):
    """Update system settings"""
    try:
        # Validate settings before saving
        if not validate_settings(new_settings):
            return False
        
        # Update configuration
        global config
        config.update(new_settings)
        
        # Save to file
        with open('config.yml', 'w') as f:
            yaml.dump(config, f, default_flow_style=False)
        
        return True
    except Exception as e:
        logger.error(f"Error updating settings: {e}")
        return False

def validate_settings(settings):
    """Validate configuration settings"""
    try:
        # Add validation logic here
        required_sections = ['recognition', 'camera', 'greeting', 'storage']
        for section in required_sections:
            if section not in settings:
                return False
        return True
    except Exception:
        return False

def get_system_stats():
    """Get system statistics"""
    try:
        import psutil
        
        # System stats
        cpu_percent = psutil.cpu_percent()
        memory = psutil.virtual_memory()
        disk = psutil.disk_usage('/')
        
        # Face stats
        known_faces = len(list_known_faces())
        unknown_faces = len(list_unknown_faces())
        
        # Camera status
        camera_active = check_camera_status()
        
        return {
            'cpu_percent': cpu_percent,
            'memory_percent': memory.percent,
            'disk_percent': disk.percent,
            'known_faces': known_faces,
            'unknown_faces': unknown_faces,
            'camera_active': camera_active,
            'last_updated': datetime.now().isoformat()
        }
    except Exception as e:
        logger.error(f"Error getting system stats: {e}")
        return {}

def check_camera_status():
    """Check if camera is active"""
    try:
        import cv2
        cap = cv2.VideoCapture(config['camera']['device'])
        status = cap.isOpened()
        cap.release()
        return status
    except Exception:
        return False

if __name__ == '__main__':
    # Run the application
    ssl_context = None
    if config['web_interface']['ssl_enabled']:
        ssl_context = (
            config['web_interface']['ssl_cert'],
            config['web_interface']['ssl_key']
        )
    
    app.run(
        host=config['web_interface']['host'],
        port=config['web_interface']['port'],
        ssl_context=ssl_context,
        debug=config['debug']['enabled']
    ) 