#!/bin/bash

# SyHub Setup Script
# Sets up IoT monitoring system on Raspberry Pi 3B with Raspberry Pi OS 64-bit Lite
# Date: April 18, 2025

set -e

# Determine the invoking user's home directory
if [ -n "$SUDO_USER" ]; then
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
    USER_HOME="$HOME"
fi

# Set default log file
LOG_FILE="/tmp/syhub_setup.log"

# Logging function
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    # Ensure log file directory exists
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# Ask yes/no question with default answer
ask_yes_no() {
    local prompt="$1"
    local default="$2"
    local response
    
    if [[ "$default" == "Y" || "$default" == "y" ]]; then
        prompt="$prompt [Y/n]: "
        default="Y"
    else
        prompt="$prompt [y/N]: "
        default="N"
    fi
    
    read -p "$prompt" response
    response=${response:-$default}
    
    if [[ "$response" =~ ^[Yy]$ ]]; then
        return 0  # Yes
    else
        return 1  # No
    fi
}

# Fix locale settings
fix_locale() {
    if ask_yes_no "Configure locale settings?" "Y"; then
        log "INFO" "Configuring locale settings..."
        sudo locale-gen en_GB.UTF-8
        sudo update-locale LANG=en_GB.UTF-8 LC_ALL=en_GB.UTF-8 LC_CTYPE=en_GB.UTF-8
        export LANG=en_GB.UTF-8
        export LC_ALL=en_GB.UTF-8
        export LC_CTYPE=en_GB.UTF-8
        log "INFO" "Locale settings configured successfully."
    else
        log "INFO" "Skipping locale configuration."
    fi
}

# Read config.yml
CONFIG_FILE="$USER_HOME/syhub/config/config.yml"

# Install mikefarah/yq
install_yq() {
    if ask_yes_no "Install mikefarah/yq (YAML processor)?" "Y"; then
        log "INFO" "Installing mikefarah/yq..."
        YQ_VERSION="v4.44.3"
        wget "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_arm64" -O /tmp/yq || { log "ERROR" "Failed to download yq"; exit 1; }
        sudo mv /tmp/yq /usr/bin/yq
        sudo chmod +x /usr/bin/yq
        log "INFO" "yq installed successfully."
    else
        log "INFO" "Skipping yq installation. Note: This tool is required for parsing the config file."
        if ! command -v yq &>/dev/null; then
            log "ERROR" "yq is not installed, but is required for this script."
            exit 1
        fi
    fi
}

# Check and install yq
if ! command -v yq &>/dev/null || ! yq --version | grep -q "mikefarah"; then
    install_yq
fi

# Verify config.yml exists
if [ ! -f "$CONFIG_FILE" ]; then
    log "ERROR" "Configuration file $CONFIG_FILE not found"
    exit 1
fi

# Parse config.yml with error handling
PROJECT_NAME=$(yq e '.project.name' "$CONFIG_FILE" || { log "ERROR" "Failed to parse project.name from $CONFIG_FILE"; exit 1; })
BASE_DIR=$(yq e '.base_dir // "'"$USER_HOME/syhub"'"' "$CONFIG_FILE" || { log "ERROR" "Failed to parse base_dir from $CONFIG_FILE"; exit 1; })
# Update LOG_FILE if specified in config.yml
NEW_LOG_FILE=$(yq e '.log_file' "$CONFIG_FILE" || { log "ERROR" "Failed to parse log_file from $CONFIG_FILE"; exit 1; })
[ -n "$NEW_LOG_FILE" ] && LOG_FILE="$NEW_LOG_FILE"
BACKUP_DIR=$(yq e '.backup_directory' "$CONFIG_FILE" || { log "ERROR" "Failed to parse backup_directory from $CONFIG_FILE"; exit 1; })
SYSTEM_USER=$(whoami)
HOSTNAME=$(yq e '.hostname' "$CONFIG_FILE" || { log "ERROR" "Failed to parse hostname from $CONFIG_FILE"; exit 1; })
CONFIGURE_NETWORK=$(yq e '.configure_network' "$CONFIG_FILE" || { log "ERROR" "Failed to parse configure_network from $CONFIG_FILE"; exit 1; })
WIFI_AP_INTERFACE=$(yq e '.wifi.ap_interface' "$CONFIG_FILE" || { log "ERROR" "Failed to parse wifi.ap_interface from $CONFIG_FILE"; exit 1; })
WIFI_AP_IP=$(yq e '.wifi.ap_ip' "$CONFIG_FILE" || { log "ERROR" "Failed to parse wifi.ap_ip from $CONFIG_FILE"; exit 1; })
WIFI_AP_SUBNET_MASK=$(yq e '.wifi.ap_subnet_mask' "$CONFIG_FILE" || { log "ERROR" "Failed to parse wifi.ap_subnet_mask from $CONFIG_FILE"; exit 1; })
WIFI_AP_DHCP_RANGE_START=$(yq e '.wifi.ap_dhcp_range_start' "$CONFIG_FILE" || { log "ERROR" "Failed to parse wifi.ap_dhcp_range_start from $CONFIG_FILE"; exit 1; })
WIFI_AP_DHCP_RANGE_END=$(yq e '.wifi.ap_dhcp_range_end' "$CONFIG_FILE" || { log "ERROR" "Failed to parse wifi.ap_dhcp_range_end from $CONFIG_FILE"; exit 1; })
WIFI_AP_DHCP_LEASE_TIME=$(yq e '.wifi.ap_dhcp_lease_time' "$CONFIG_FILE" || { log "ERROR" "Failed to parse wifi.ap_dhcp_lease_time from $CONFIG_FILE"; exit 1; })
WIFI_AP_SSID=$(yq e '.wifi.ap_ssid' "$CONFIG_FILE" || { log "ERROR" "Failed to parse wifi.ap_ssid from $CONFIG_FILE"; exit 1; })
WIFI_AP_PASSWORD=$(yq e '.wifi.ap_password' "$CONFIG_FILE" || { log "ERROR" "Failed to parse wifi.ap_password from $CONFIG_FILE"; exit 1; })
WIFI_COUNTRY_CODE=$(yq e '.wifi.country_code' "$CONFIG_FILE" || { log "ERROR" "Failed to parse wifi.country_code from $CONFIG_FILE"; exit 1; })
WIFI_STA_SSID=$(yq e '.wifi.sta_ssid' "$CONFIG_FILE" || { log "ERROR" "Failed to parse wifi.sta_ssid from $CONFIG_FILE"; exit 1; })
WIFI_STA_PASSWORD=$(yq e '.wifi.sta_password' "$CONFIG_FILE" || { log "ERROR" "Failed to parse wifi.sta_password from $CONFIG_FILE"; exit 1; })
MQTT_PORT=$(yq e '.mqtt.port' "$CONFIG_FILE" || { log "ERROR" "Failed to parse mqtt.port from $CONFIG_FILE"; exit 1; })
MQTT_USERNAME=$(yq e '.mqtt.username' "$CONFIG_FILE" || { log "ERROR" "Failed to parse mqtt.username from $CONFIG_FILE"; exit 1; })
MQTT_PASSWORD=$(yq e '.mqtt.password' "$CONFIG_FILE" || { log "ERROR" "Failed to parse mqtt.password from $CONFIG_FILE"; exit 1; })
MQTT_TOPIC=$(yq e '.mqtt.topic_telemetry' "$CONFIG_FILE" || { log "ERROR" "Failed to parse mqtt.topic_telemetry from $CONFIG_FILE"; exit 1; })
VICTORIA_METRICS_VERSION=$(yq e '.victoria_metrics.version' "$CONFIG_FILE" || { log "ERROR" "Failed to parse victoria_metrics.version from $CONFIG_FILE"; exit 1; })
VICTORIA_METRICS_PORT=$(yq e '.victoria_metrics.port' "$CONFIG_FILE" || { log "ERROR" "Failed to parse victoria_metrics.port from $CONFIG_FILE"; exit 1; })
VICTORIA_METRICS_DATA_DIR=$(yq e '.victoria_metrics.data_directory' "$CONFIG_FILE" || { log "ERROR" "Failed to parse victoria_metrics.data_directory from $CONFIG_FILE"; exit 1; })
VICTORIA_METRICS_RETENTION=$(yq e '.victoria_metrics.retention_period' "$CONFIG_FILE" || { log "ERROR" "Failed to parse victoria_metrics.retention_period from $CONFIG_FILE"; exit 1; })
VICTORIA_METRICS_USER=$(yq e '.victoria_metrics.service_user' "$CONFIG_FILE" || { log "ERROR" "Failed to parse victoria_metrics.service_user from $CONFIG_FILE"; exit 1; })
VICTORIA_METRICS_GROUP=$(yq e '.victoria_metrics.service_group' "$CONFIG_FILE" || { log "ERROR" "Failed to parse victoria_metrics.service_group from $CONFIG_FILE"; exit 1; })
NODE_RED_PORT=$(yq e '.node_red.port' "$CONFIG_FILE" || { log "ERROR" "Failed to parse node_red.port from $CONFIG_FILE"; exit 1; })
NODE_RED_MEMORY_LIMIT=$(yq e '.node_red.memory_limit_mb' "$CONFIG_FILE" || { log "ERROR" "Failed to parse node_red.memory_limit_mb from $CONFIG_FILE"; exit 1; })
NODE_RED_USERNAME=$(yq e '.node_red.username' "$CONFIG_FILE" || { log "ERROR" "Failed to parse node_red.username from $CONFIG_FILE"; exit 1; })
NODE_RED_PASSWORD_HASH=$(yq e '.node_red.password_hash' "$CONFIG_FILE" || { log "ERROR" "Failed to parse node_red.password_hash from $CONFIG_FILE"; exit 1; })
DASHBOARD_PORT=$(yq e '.dashboard.port' "$CONFIG_FILE" || { log "ERROR" "Failed to parse dashboard.port from $CONFIG_FILE"; exit 1; })
DASHBOARD_WORKERS=$(yq e '.dashboard.workers' "$CONFIG_FILE" || { log "ERROR" "Failed to parse dashboard.workers from $CONFIG_FILE"; exit 1; })
NODEJS_VERSION=$(yq e '.nodejs.install_version' "$CONFIG_FILE" || { log "ERROR" "Failed to parse nodejs.install_version from $CONFIG_FILE"; exit 1; })

# Error handling function
handle_error() {
    log "ERROR" "Failed at step: $1"
    exit 1
}

# Check internet connectivity
check_internet() {
    if ask_yes_no "Check internet connectivity?" "Y"; then
        log "INFO" "Checking internet connectivity..."
        for i in {1..3}; do
            if ping -c 1 github.com &>/dev/null; then
                log "INFO" "Internet connection verified."
                return 0
            fi
            log "WARNING" "No internet connection. Retrying ($i/3)..."
            sleep 5
        done
        handle_error "Internet connectivity check"
    else
        log "INFO" "Skipping internet connectivity check."
    fi
}

# Install dependencies
install_dependencies() {
    if ask_yes_no "Update package lists?" "Y"; then
        log "INFO" "Updating package lists..."
        sudo apt update 2>&1 | tee -a "$LOG_FILE" || handle_error "APT update"
    else
        log "INFO" "Skipping package list update."
    fi

    if ask_yes_no "Install core dependencies (Python, Git, etc.)?" "Y"; then
        log "INFO" "Installing core dependencies..."
        sudo apt install -y \
            python3 \
            python3-flask python3-gunicorn python3-requests python3-paho-mqtt python3-yaml \
            git wget curl \
            2>&1 | tee -a "$LOG_FILE" || handle_error "Core dependency installation"
    else
        log "INFO" "Skipping core dependency installation."
    fi

    if ask_yes_no "Install network tools (hostapd, dnsmasq)?" "Y"; then
        log "INFO" "Installing network tools..."
        sudo apt install -y \
            hostapd dnsmasq avahi-daemon \
            2>&1 | tee -a "$LOG_FILE" || handle_error "Network tools installation"
    else
        log "INFO" "Skipping network tools installation."
    fi

    if ask_yes_no "Install Node.js v$NODEJS_VERSION?" "Y"; then
        log "INFO" "Installing Node.js..."
        curl -fsSL https://deb.nodesource.com/setup_"$NODEJS_VERSION".x | sudo -E bash -
        sudo apt install -y nodejs 2>&1 | tee -a "$LOG_FILE" || handle_error "Node.js installation"
        log "INFO" "Node.js installed successfully."
    else
        log "INFO" "Skipping Node.js installation."
    fi
}

# Configure WiFi AP+STA
configure_wifi() {
    if [ "$CONFIGURE_NETWORK" != "true" ]; then
        log "INFO" "Skipping network configuration (configure_network=false in config)"
        return
    fi

    if ask_yes_no "Configure WiFi Access Point + Station?" "Y"; then
        log "INFO" "Configuring WiFi AP+STA..."
        # Verify templates exist
        for template in dhcpcd.conf.j2 dnsmasq.conf.j2 hostapd.conf.j2; do
            [ -f "$BASE_DIR/config/$template" ] || handle_error "Missing template: $template"
        done

        sudo mv /etc/dhcpcd.conf /etc/dhcpcd.conf.bak-$(date +%F) 2>/dev/null || true
        sudo mv /etc/dnsmasq.conf /etc/dnsmasq.conf.bak-$(date +%F) 2>/dev/null || true
        sudo mv /etc/hostapd/hostapd.conf /etc/hostapd/hostapd.conf.bak-$(date +%F) 2>/dev/null || true

        for template in dhcpcd.conf.j2 dnsmasq.conf.j2 hostapd.conf.j2; do
            sed -e "s|__WIFI_AP_INTERFACE__|$WIFI_AP_INTERFACE|" \
                -e "s|__WIFI_AP_IP__|$WIFI_AP_IP|" \
                -e "s|__WIFI_AP_SUBNET_MASK__|$WIFI_AP_SUBNET_MASK|" \
                -e "s|__WIFI_AP_DHCP_RANGE_START__|$WIFI_AP_DHCP_RANGE_START|" \
                -e "s|__WIFI_AP_DHCP_RANGE_END__|$WIFI_AP_DHCP_RANGE_END|" \
                -e "s|__WIFI_AP_DHCP_LEASE_TIME__|$WIFI_AP_DHCP_LEASE_TIME|" \
                -e "s|__WIFI_AP_SSID__|$WIFI_AP_SSID|" \
                -e "s|__WIFI_AP_PASSWORD__|$WIFI_AP_PASSWORD|" \
                -e "s|__WIFI_COUNTRY_CODE__|$WIFI_COUNTRY_CODE|" \
                -e "s|__WIFI_STA_SSID__|$WIFI_STA_SSID|" \
                -e "s|__WIFI_STA_PASSWORD__|$WIFI_STA_PASSWORD|" \
                "$BASE_DIR/config/$template" > "/tmp/${template%.j2}" || handle_error "Template processing: $template"
            
            sudo mv "/tmp/${template%.j2}" "/etc/${template%.j2}"
        done

        sudo systemctl unmask hostapd
        sudo systemctl enable hostapd dnsmasq
        sudo systemctl restart hostapd dnsmasq || handle_error "WiFi service restart"
        log "INFO" "WiFi AP+STA configured successfully."
    else
        log "INFO" "Skipping WiFi configuration."
    fi
}

# Configure Mosquitto 
configure_mosquitto() {
    if ask_yes_no "Install and configure Mosquitto MQTT broker?" "Y"; then
        log "INFO" "Installing Mosquitto MQTT broker..."
        sudo apt install -y mosquitto mosquitto-clients || handle_error "Mosquitto installation"
        
        log "INFO" "Configuring Mosquitto MQTT broker..."
        
        # Backup existing configuration
        [ -f "/etc/mosquitto/mosquitto.conf" ] && sudo mv /etc/mosquitto/mosquitto.conf /etc/mosquitto/mosquitto.conf.bak-$(date +%F)
        [ -f "/etc/mosquitto/conf.d/$PROJECT_NAME.conf" ] && sudo mv /etc/mosquitto/conf.d/$PROJECT_NAME.conf /etc/mosquitto/conf.d/$PROJECT_NAME.conf.bak-$(date +%F)
        
        # Create main configuration file
        cat << EOF | sudo tee /etc/mosquitto/mosquitto.conf
# Mosquitto main configuration
per_listener_settings true
pid_file /run/mosquitto/mosquitto.pid
persistence true
persistence_location /var/lib/mosquitto/
log_dest file /var/log/mosquitto/mosquitto.log
include_dir /etc/mosquitto/conf.d
EOF

        # Create password file
        sudo rm -f /etc/mosquitto/passwd
        sudo touch /etc/mosquitto/passwd
        sudo mosquitto_passwd -b /etc/mosquitto/passwd "$MQTT_USERNAME" "$MQTT_PASSWORD" || handle_error "Mosquitto password creation"
        sudo chown mosquitto:mosquitto /etc/mosquitto/passwd
        sudo chmod 600 /etc/mosquitto/passwd

        # Create listener configuration
        sudo mkdir -p /etc/mosquitto/conf.d
        cat << EOF | sudo tee /etc/mosquitto/conf.d/$PROJECT_NAME.conf
# $PROJECT_NAME MQTT Listener Configuration
listener $MQTT_PORT
protocol mqtt
allow_anonymous false
password_file /etc/mosquitto/passwd
EOF

        # Ensure correct permissions
        sudo chown mosquitto:mosquitto /etc/mosquitto/conf.d/$PROJECT_NAME.conf
        sudo chmod 644 /etc/mosquitto/conf.d/$PROJECT_NAME.conf

        sudo systemctl enable mosquitto
        sudo systemctl restart mosquitto || handle_error "Mosquitto service restart"
        log "INFO" "Mosquitto configured successfully."
    else
        log "INFO" "Skipping Mosquitto installation and configuration."
    fi
}

# Configure VictoriaMetrics
configure_victoriametrics() {
    if ask_yes_no "Install and configure VictoriaMetrics?" "Y"; then
        log "INFO" "Configuring VictoriaMetrics..."
        sudo useradd -r -s /bin/false "$VICTORIA_METRICS_USER" 2>/dev/null || true
        sudo groupadd "$VICTORIA_METRICS_GROUP" 2>/dev/null || true
        sudo usermod -a -G "$VICTORIA_METRICS_GROUP" "$VICTORIA_METRICS_USER"

        sudo mkdir -p "$VICTORIA_METRICS_DATA_DIR"
        sudo chown "$VICTORIA_METRICS_USER:$VICTORIA_METRICS_GROUP" "$VICTORIA_METRICS_DATA_DIR"

        log "INFO" "Downloading VictoriaMetrics v$VICTORIA_METRICS_VERSION..."
        wget "https://github.com/VictoriaMetrics/VictoriaMetrics/releases/download/$VICTORIA_METRICS_VERSION/victoria-metrics-linux-arm64-$VICTORIA_METRICS_VERSION.tar.gz" -O /tmp/vm.tar.gz || handle_error "VictoriaMetrics download"
        sudo tar -xzf /tmp/vm.tar.gz -C /usr/local/bin
        sudo mv /usr/local/bin/victoria-metrics-prod /usr/local/bin/victoria-metrics
        sudo chmod +x /usr/local/bin/victoria-metrics

        cat << EOF | sudo tee /etc/systemd/system/victoriametrics.service
[Unit]
Description=VictoriaMetrics Time Series Database
After=network.target

[Service]
ExecStart=/usr/local/bin/victoria-metrics -httpListenAddr=:$VICTORIA_METRICS_PORT -retentionPeriod=$VICTORIA_METRICS_RETENTION -storageDataPath=$VICTORIA_METRICS_DATA_DIR
User=$VICTORIA_METRICS_USER
Group=$VICTORIA_METRICS_GROUP
Restart=always

[Install]
WantedBy=multi-user.target
EOF

        sudo systemctl daemon-reload
        sudo systemctl enable victoriametrics
        sudo systemctl restart victoriametrics || handle_error "VictoriaMetrics service restart"
        log "INFO" "VictoriaMetrics configured successfully."
    else
        log "INFO" "Skipping VictoriaMetrics installation and configuration."
    fi
}

# Configure Node-RED
configure_nodered() {
    if ask_yes_no "Install and configure Node-RED?" "Y"; then
        log "INFO" "Installing and configuring Node-RED..."
        sudo npm install -g --unsafe-perm node-red
        mkdir -p "$BASE_DIR/.node-red"
        
        # Check if settings.js file exists
        if [ -f "$BASE_DIR/.node-red/settings.js" ]; then
            sed -e "s|__BASE_DIR__|$BASE_DIR|" \
                -e "s|__NODE_RED_USERNAME__|$NODE_RED_USERNAME|" \
                -e "s|__NODE_RED_PASSWORD_HASH__|$NODE_RED_PASSWORD_HASH|" \
                "$BASE_DIR/.node-red/settings.js" > "$BASE_DIR/.node-red/settings.js.tmp" && mv "$BASE_DIR/.node-red/settings.js.tmp" "$BASE_DIR/.node-red/settings.js" || handle_error "Node-RED settings processing"
        else
            log "WARNING" "settings.js not found at $BASE_DIR/.node-red/settings.js"
        fi

        # Check if flows.json file exists
        if [ -f "$BASE_DIR/.node-red/flows.json" ]; then
            sed -e "s|__MQTT_TOPIC__|$MQTT_TOPIC|" \
                -e "s|__HOSTNAME__|$HOSTNAME|" \
                -e "s|__VICTORIA_METRICS_PORT__|$VICTORIA_METRICS_PORT|" \
                -e "s|__MQTT_PORT__|$MQTT_PORT|" \
                -e "s|__PROJECT_NAME__|$PROJECT_NAME|" \
                -e "s|__MQTT_USERNAME__|$MQTT_USERNAME|" \
                -e "s|__MQTT_PASSWORD__|$MQTT_PASSWORD|" \
                "$BASE_DIR/.node-red/flows.json" > "$BASE_DIR/.node-red/flows.json.tmp" && mv "$BASE_DIR/.node-red/flows.json.tmp" "$BASE_DIR/.node-red/flows.json" || handle_error "Node-RED flows processing"
        else
            log "WARNING" "flows.json not found at $BASE_DIR/.node-red/flows.json"
        fi

        cat << EOF | sudo tee /etc/systemd/system/nodered.service
[Unit]
Description=Node-RED
After=network.target

[Service]
ExecStart=/usr/bin/node-red --max-old-space-size=$NODE_RED_MEMORY_LIMIT -p $NODE_RED_PORT
WorkingDirectory=$BASE_DIR/.node-red
User=$SUDO_USER
Restart=always
Environment=NODE_RED_HOME=$BASE_DIR/.node-red

[Install]
WantedBy=multi-user.target
EOF

        sudo systemctl daemon-reload
        sudo systemctl enable nodered
        sudo systemctl restart nodered || handle_error "Node-RED service restart"
        log "INFO" "Node-RED configured successfully."
    else
        log "INFO" "Skipping Node-RED installation and configuration."
    fi
}

# Configure Data Processor
configure_data_processor() {
    if ask_yes_no "Configure Data Processor service?" "Y"; then
        log "INFO" "Configuring Data Processor..."
        cat << EOF | sudo tee /etc/systemd/system/$PROJECT_NAME-processor.service
[Unit]
Description=$PROJECT_NAME Data Processor
After=network.target mosquitto.service victoriametrics.service

[Service]
ExecStart=/usr/bin/python3 $BASE_DIR/src/data_processor.py
WorkingDirectory=$BASE_DIR/src
Restart=always
User=$SUDO_USER

[Install]
WantedBy=multi-user.target
EOF

        sudo systemctl daemon-reload
        sudo systemctl enable "$PROJECT_NAME"-processor
        sudo systemctl restart "$PROJECT_NAME"-processor || handle_error "Data Processor service restart"
        log "INFO" "Data Processor configured successfully."
    else
        log "INFO" "Skipping Data Processor configuration."
    fi
}

# Configure Alerter
configure_alerter() {
    if ask_yes_no "Configure Alerter service?" "Y"; then
        log "INFO" "Configuring Alerter..."
        cat << EOF | sudo tee /etc/systemd/system/$PROJECT_NAME-alerter.service
[Unit]
Description=$PROJECT_NAME Alerter
After=network.target victoriametrics.service

[Service]
ExecStart=/usr/bin/python3 $BASE_DIR/src/alerter.py
WorkingDirectory=$BASE_DIR/src
Restart=always
User=$SUDO_USER

[Install]
WantedBy=multi-user.target
EOF

        sudo systemctl daemon-reload
        sudo systemctl enable "$PROJECT_NAME"-alerter
        sudo systemctl restart "$PROJECT_NAME"-alerter || handle_error "Alerter service restart"
        log "INFO" "Alerter configured successfully."
    else
        log "INFO" "Skipping Alerter configuration."
    fi
}

# Configure Flask Dashboard
configure_dashboard() {
    if ask_yes_no "Configure Flask Dashboard service?" "Y"; then
        log "INFO" "Configuring Flask Dashboard..."
        # Ensure the static directory exists
        mkdir -p "$BASE_DIR/src/static"
        mkdir -p "/var/log/$PROJECT_NAME" "/var/run/$PROJECT_NAME"
        sudo chown -R "$SUDO_USER:$SUDO_USER" "/var/log/$PROJECT_NAME" "/var/run/$PROJECT_NAME"
        
        # Check if index.html file exists
        if [ -f "$BASE_DIR/src/static/index.html" ]; then
            sed -e "s|__PROJECT_NAME__|$PROJECT_NAME|" \
                "$BASE_DIR/src/static/index.html" > "$BASE_DIR/src/static/index.html.tmp" && mv "$BASE_DIR/src/static/index.html.tmp" "$BASE_DIR/src/static/index.html" || handle_error "Index.html processing"
        else
            log "WARNING" "index.html not found at $BASE_DIR/src/static/index.html"
        fi

        # Create Gunicorn configuration file
        log "INFO" "Creating Gunicorn configuration file..."
        cat << EOF > "$BASE_DIR/src/gunicorn.conf.py"
# Gunicorn configuration file for $PROJECT_NAME
import multiprocessing
import os

# Server socket
bind = "0.0.0.0:$DASHBOARD_PORT"
backlog = 2048

# Worker processes - better CPU utilization
workers = multiprocessing.cpu_count() * 2 + 1
worker_class = 'gthread'
threads = 2
worker_connections = 1000
timeout = 30
keepalive = 2

# Process naming
proc_name = '$PROJECT_NAME-dashboard'
pythonpath = '$BASE_DIR/src'

# Logging
accesslog = '/var/log/$PROJECT_NAME/access.log'
errorlog = '/var/log/$PROJECT_NAME/error.log'
loglevel = 'info'
access_log_format = '%({X-Real-IP}i)s %(l)s %(u)s %(t)s "%(r)s" %(s)s %(b)s "%(f)s" "%(a)s"'

# Server mechanics
daemon = False
pidfile = '/var/run/$PROJECT_NAME/gunicorn.pid'
umask = 0o27
user = '$SUDO_USER'
group = '$SUDO_USER'

# Max requests
max_requests = 1000
max_requests_jitter = 50

# Environment variables
raw_env = [
    "PYTHONUNBUFFERED=1",
    "WEB_CONCURRENCY=2"
]

# Ensure directories exist
os.makedirs('/var/log/$PROJECT_NAME', exist_ok=True)
os.makedirs('/var/run/$PROJECT_NAME', exist_ok=True)
EOF

        # Create the systemd service file
        cat << EOF | sudo tee /etc/systemd/system/$PROJECT_NAME-dashboard.service
[Unit]
Description=$PROJECT_NAME Flask Dashboard
After=network.target

[Service]
User=$SUDO_USER
Group=$SUDO_USER
WorkingDirectory=$BASE_DIR/src
ExecStart=/usr/bin/python3 -m gunicorn --config gunicorn.conf.py app:app
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=$PROJECT_NAME-dashboard
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
EOF

        sudo systemctl daemon-reload
        sudo systemctl enable "$PROJECT_NAME"-dashboard
        sudo systemctl restart "$PROJECT_NAME"-dashboard || handle_error "Dashboard service restart"
        log "INFO" "Dashboard configured successfully with optimized Gunicorn settings."
    else
        log "INFO" "Skipping Dashboard configuration."
    fi
}

# Configure Health Check
configure_health_check() {
    if ask_yes_no "Configure Health Check service?" "Y"; then
        log "INFO" "Configuring Health Check..."
        # Check if health_check.sh file exists
        if [ -f "$BASE_DIR/scripts/health_check.sh" ]; then
            sed -e "s|__PROJECT_NAME__|$PROJECT_NAME|" \
                "$BASE_DIR/scripts/health_check.sh" > "$BASE_DIR/scripts/health_check.sh.tmp" && mv "$BASE_DIR/scripts/health_check.sh.tmp" "$BASE_DIR/scripts/health_check.sh" || handle_error "Health check processing"
            chmod +x "$BASE_DIR/scripts/health_check.sh"
        else
            log "WARNING" "health_check.sh not found at $BASE_DIR/scripts/health_check.sh"
        fi

        cat << EOF | sudo tee /etc/systemd/system/$PROJECT_NAME-healthcheck.service
[Unit]
Description=$PROJECT_NAME Health Check
After=network.target

[Service]
ExecStart=/bin/bash $BASE_DIR/scripts/health_check.sh
WorkingDirectory=$BASE_DIR/scripts
Restart=always
User=$SUDO_USER

[Install]
WantedBy=multi-user.target
EOF

        sudo systemctl daemon-reload
        sudo systemctl enable "$PROJECT_NAME"-healthcheck
        sudo systemctl restart "$PROJECT_NAME"-healthcheck || handle_error "Health Check service restart"
        log "INFO" "Health Check configured successfully."
    else
        log "INFO" "Skipping Health Check configuration."
    fi
}

# Configure backup cron job
configure_backup() {
    if ask_yes_no "Configure automated backups?" "Y"; then
        log "INFO" "Setting up backup cron job..."
        
        # Ensure backup directory exists
        mkdir -p "$BASE_DIR/$BACKUP_DIR"
        
        # Add cron job for daily backups
        (crontab -l 2>/dev/null || echo "") | grep -v "$BASE_DIR/scripts/setup.sh backup" | echo "0 0 * * * /bin/bash $BASE_DIR/scripts/setup.sh backup" | crontab -
        
        log "INFO" "Backup cron job configured successfully."
    else
        log "INFO" "Skipping backup configuration."
    fi
}

# Main setup function
main() {
    log "INFO" "Starting $PROJECT_NAME setup..."
    echo "========================================"
    echo "  $PROJECT_NAME Installation Script"
    echo "========================================"
    echo "This script will set up various components for your IoT system."
    echo "You can choose which components to install."
    echo ""

    fix_locale
    check_internet
    install_dependencies
    configure_wifi
    configure_mosquitto
    configure_victoriametrics
    configure_nodered
    configure_data_processor
    configure_alerter
    configure_dashboard
    configure_health_check
    configure_backup

    log "INFO" "Setup completed successfully!"
    echo ""
    echo "========================================"
    echo "  Installation Complete!"
    echo "========================================"
    echo "You can access the dashboard at: http://$HOSTNAME:$DASHBOARD_PORT"
    echo "Node-RED interface is available at: http://$HOSTNAME:$NODE_RED_PORT"
    echo ""
}

# Backup function
backup() {
    log "INFO" "Creating backup..."
    
    # Ensure backup directory exists
    mkdir -p "$BASE_DIR/$BACKUP_DIR"
    
    # Create backup with timestamp
    BACKUP_FILE="$BASE_DIR/$BACKUP_DIR/backup-$(date +%F).tar.gz"
    tar -czf "$BACKUP_FILE" "$BASE_DIR/config" "$BASE_DIR/src" "$BASE_DIR/.node-red" > /dev/null 2>&1 || handle_error "Backup creation"
    
    log "INFO" "Backup created at: $BACKUP_FILE"
}

# Show info function
show_info() {
    echo "========================================"
    echo "  $PROJECT_NAME System Information"
    echo "========================================"
    echo "Project Name: $PROJECT_NAME"
    echo "Installation Directory: $BASE_DIR"
    echo "Hostname: $HOSTNAME"
    
    # Check service status
    echo ""
    echo "Services Status:"
    for service in mosquitto victoriametrics nodered "$PROJECT_NAME"-processor "$PROJECT_NAME"-alerter "$PROJECT_NAME"-dashboard "$PROJECT_NAME"-healthcheck; do
        if systemctl is-active --quiet "$service"; then
            echo "  $service: RUNNING"
        else
            echo "  $service: STOPPED"
        fi
    done
    
    # Show URLs
    echo ""
    echo "Access URLs:"
    echo "  Dashboard: http://$HOSTNAME:$DASHBOARD_PORT"
    echo "  Node-RED: http://$HOSTNAME:$NODE_RED_PORT"
    echo "  VictoriaMetrics: http://$HOSTNAME:$VICTORIA_METRICS_PORT"
    
    # Show credentials
    echo ""
    echo "Credentials:"
    echo "  MQTT Username: $MQTT_USERNAME"
    echo "  Node-RED Username: $NODE_RED_USERNAME"
}

# Handle script arguments
case "$1" in
    setup)
        main
        ;;
    backup)
        backup
        ;;
    info)
        show_info
        ;;
    *)
        echo "Usage: $0 {setup|backup|info}"
        echo ""
        echo "Commands:"
        echo "  setup    Install and configure the system"
        echo "  backup   Create a backup of configuration files"
        echo "  info     Display system information"
        exit 1
        ;;
esac