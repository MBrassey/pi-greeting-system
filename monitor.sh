#!/bin/bash

# System Monitoring Script for Raspberry Pi Facial Recognition System
# Provides real-time monitoring of system performance and status

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

# Check for required tools
for cmd in top free df vcgencmd curl jq; do
    if ! command -v $cmd &> /dev/null; then
        error "$cmd is required but not installed."
        exit 1
    fi
done

# Function to get CPU temperature
get_cpu_temp() {
    if [ -f "/sys/class/thermal/thermal_zone0/temp" ]; then
        temp=$(cat /sys/class/thermal/thermal_zone0/temp)
        echo "scale=1; $temp/1000" | bc
    else
        echo "N/A"
    fi
}

# Function to get GPU temperature
get_gpu_temp() {
    if command -v vcgencmd &> /dev/null; then
        vcgencmd measure_temp | cut -d'=' -f2 | cut -d"'" -f1
    else
        echo "N/A"
    fi
}

# Function to get system stats
get_system_stats() {
    # CPU Usage
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}')
    
    # Memory Usage
    mem_total=$(free -m | awk 'NR==2 {print $2}')
    mem_used=$(free -m | awk 'NR==2 {print $3}')
    mem_percent=$((mem_used * 100 / mem_total))
    
    # Disk Usage
    disk_usage=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
    
    # Temperatures
    cpu_temp=$(get_cpu_temp)
    gpu_temp=$(get_gpu_temp)
    
    # Network
    rx_bytes=$(cat /sys/class/net/$(ip route | grep default | awk '{print $5}')/statistics/rx_bytes)
    tx_bytes=$(cat /sys/class/net/$(ip route | grep default | awk '{print $5}')/statistics/tx_bytes)
    
    echo "CPU Usage: ${cpu_usage}%"
    echo "Memory: ${mem_used}MB/${mem_total}MB (${mem_percent}%)"
    echo "Disk Usage: ${disk_usage}%"
    echo "CPU Temperature: ${cpu_temp}°C"
    echo "GPU Temperature: ${gpu_temp}°C"
    echo "Network RX: $(numfmt --to=iec-i --suffix=B $rx_bytes)"
    echo "Network TX: $(numfmt --to=iec-i --suffix=B $tx_bytes)"
}

# Function to get service status
get_service_status() {
    local service=$1
    status=$(systemctl is-active $service)
    active_time=$(systemctl show $service --property=ActiveEnterTimestamp | cut -d'=' -f2)
    
    if [ "$status" = "active" ]; then
        echo -e "${GREEN}●${NC} Active since $active_time"
    else
        echo -e "${RED}●${NC} $status"
    fi
}

# Function to get process stats
get_process_stats() {
    local process_name=$1
    if pgrep -f "$process_name" > /dev/null; then
        pid=$(pgrep -f "$process_name")
        cpu=$(ps -p $pid -o %cpu | tail -1)
        mem=$(ps -p $pid -o %mem | tail -1)
        runtime=$(ps -p $pid -o etime | tail -1)
        echo -e "${GREEN}●${NC} Running (PID: $pid, CPU: ${cpu}%, MEM: ${mem}%, Runtime: $runtime)"
    else
        echo -e "${RED}●${NC} Not running"
    fi
}

# Function to check camera status
check_camera() {
    if [ -e "/dev/video0" ]; then
        echo -e "${GREEN}●${NC} Connected (/dev/video0)"
    elif vcgencmd get_camera | grep -q "supported=1 detected=1"; then
        echo -e "${GREEN}●${NC} Pi Camera connected"
    else
        echo -e "${RED}●${NC} No camera detected"
    fi
}

# Function to check audio status
check_audio() {
    if command -v aplay &> /dev/null; then
        if aplay -l | grep -q "card"; then
            echo -e "${GREEN}●${NC} Audio device found"
        else
            echo -e "${RED}●${NC} No audio device found"
        fi
    else
        echo -e "${YELLOW}●${NC} Cannot check audio (aplay not installed)"
    fi
}

# Function to check web interface
check_web_interface() {
    if curl -s http://localhost:8080 > /dev/null; then
        echo -e "${GREEN}●${NC} Responding"
    else
        echo -e "${RED}●${NC} Not responding"
    fi
}

# Function to get face detection stats
get_face_stats() {
    known_faces=$(ls -1 data/known_faces | wc -l)
    unknown_faces=$(ls -1 data/unknown_faces | wc -l)
    echo "Known Faces: $known_faces"
    echo "Unknown Faces: $unknown_faces"
}

# Function to check disk space
check_disk_space() {
    local dir=$1
    local usage=$(df -h $dir | awk 'NR==2 {print $5}' | tr -d '%')
    local free=$(df -h $dir | awk 'NR==2 {print $4}')
    
    if [ $usage -gt 90 ]; then
        echo -e "${RED}●${NC} Critical: $usage% used ($free free)"
    elif [ $usage -gt 75 ]; then
        echo -e "${YELLOW}●${NC} Warning: $usage% used ($free free)"
    else
        echo -e "${GREEN}●${NC} OK: $usage% used ($free free)"
    fi
}

# Function to check log files
check_logs() {
    local log_dir="/var/log/facial-recognition"
    if [ -d "$log_dir" ]; then
        local size=$(du -sh $log_dir | cut -f1)
        local errors=$(grep -i "error" $log_dir/*.log 2>/dev/null | wc -l)
        echo "Log Size: $size"
        if [ $errors -gt 0 ]; then
            echo -e "${YELLOW}Recent Errors: $errors${NC}"
        fi
    else
        echo -e "${RED}Log directory not found${NC}"
    fi
}

# Main monitoring loop
clear
while true; do
    # Get terminal size
    term_width=$(tput cols)
    
    # Print header
    printf "%${term_width}s\n" | tr " " "="
    echo -e "${GREEN}Raspberry Pi Facial Recognition System Monitor${NC}"
    echo -e "Updated: $(date '+%Y-%m-%d %H:%M:%S')"
    printf "%${term_width}s\n" | tr " " "="
    
    # System Status
    echo -e "\n${BLUE}=== System Status ===${NC}"
    get_system_stats
    
    # Service Status
    echo -e "\n${BLUE}=== Service Status ===${NC}"
    echo "Face Recognition: $(get_service_status facial-recognition)"
    echo "Web Interface: $(get_service_status facial-recognition-web)"
    
    # Process Status
    echo -e "\n${BLUE}=== Process Status ===${NC}"
    echo "Face Recognition: $(get_process_stats face_recognition.py)"
    echo "Web Interface: $(get_process_stats web_interface.py)"
    
    # Hardware Status
    echo -e "\n${BLUE}=== Hardware Status ===${NC}"
    echo "Camera: $(check_camera)"
    echo "Audio: $(check_audio)"
    
    # Storage Status
    echo -e "\n${BLUE}=== Storage Status ===${NC}"
    echo "System Disk: $(check_disk_space /)"
    echo "Data Directory: $(check_disk_space data)"
    
    # Application Status
    echo -e "\n${BLUE}=== Application Status ===${NC}"
    echo "Web Interface: $(check_web_interface)"
    get_face_stats
    
    # Log Status
    echo -e "\n${BLUE}=== Log Status ===${NC}"
    check_logs
    
    # Print footer
    printf "%${term_width}s\n" | tr " " "="
    echo -e "Press Ctrl+C to exit"
    
    # Wait before updating
    sleep 5
    clear
done 