#!/bin/bash

# syhub.sh - IoT Monitoring System Setup Script
# For resource-constrained devices like Raspberry Pi 3B
# Handles setup, update, backup, purge and status operations

set -e

# Script variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$PROJECT_DIR/config/config.yml"
LOG_FILE="/tmp/syhub_setup.log"
BACKUP_DIR="$PROJECT_DIR/backups"
TEMPLATES_DIR="$PROJECT_DIR/templates"
STATIC_DIR="$PROJECT_DIR/static"
VENV_DIR="$PROJECT_DIR/venv"

# Function to log messages
log() {
  local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
  echo "[$timestamp] $1" | tee -a $LOG_FILE
}

# Function to log errors and exit
error_exit() {
  log "ERROR: $1"
  exit 1
}

# Function to check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Function to retry a command with backoff
retry_with_backoff() {
  local max_attempts=5
  local timeout=1
  local attempt=1
  local exitCode=0

  while (( $attempt <= $max_attempts ))
  do
    if "$@"
    then
      return 0
    else
      exitCode=$?
    fi

    log "Command failed with exit code $exitCode. Retrying in $timeout seconds... (Attempt $attempt/$max_attempts)"
    sleep $timeout
    attempt=$(( attempt + 1 ))
    timeout=$(( timeout * 2 ))
  done

  log "Command failed after $max_attempts attempts. Giving up."
  return $exitCode
}

# Function to load configuration
load_config() {
  log "Loading configuration from $CONFIG_FILE"
  
  # Install yq if not already installed
  if ! command_exists yq; then
    log "Installing yq..."
    retry_with_backoff wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_arm64
    chmod +x /usr/local/bin/yq
  fi
  
  # Parse config file
  if [ ! -f "$CONFIG_FILE" ]; then
    error_exit "Configuration file not found at $CONFIG_FILE"
  fi
  
  # Validate config file
  yq e '.' "$CONFIG_FILE" > /tmp/config.yml.parsed 2> /tmp/config.yml.errors
  if [ $? -ne 0 ]; then
    cat /tmp/config.yml.errors
    error_exit "Invalid YAML in configuration file"
  fi
  
  # Extract values
  PROJECT_NAME=$(yq e '.project.name' "$CONFIG_FILE")
  HOSTNAME=$(yq e '.project.hostname // "'$PROJECT_NAME'.local"' "$CONFIG_FILE")
  WIFI_SSID=$(yq e '.project.wifi_ssid' "$CONFIG_FILE")
  WIFI_PASSWORD=$(yq e '.project.wifi_password' "$CONFIG_FILE")
  STA_WIFI_SSID=$(yq e '.project.sta_wifi_ssid' "$CONFIG_FILE")
  STA_WIFI_PASSWORD=$(yq e '.project.sta_wifi_password' "$CONFIG_FILE")
  MQTT_PORT=$(yq e '.project.mqtt.port' "$CONFIG_FILE")
  MQTT_USERNAME=$(yq e '.project.mqtt.username' "$CONFIG_FILE")
  MQTT_PASSWORD=$(yq e '.project.mqtt.password' "$CONFIG_FILE")
  MQTT_TOPIC=$(yq e '.project.mqtt.topic' "$CONFIG_FILE")
  MQTT_CLIENT_ID=$(yq e '.project.mqtt.client_id // "'$MQTT_USERNAME'"' "$CONFIG_FILE")
  MQTT_URI=$(yq e '.project.mqtt.uri // "mqtt://'$HOSTNAME'"' "$CONFIG_FILE")
  VM_PORT=$(yq e '.project.victoria_metrics.port' "$CONFIG_FILE")
  NODERED_PORT=$(yq e '.project.node_red.port' "$CONFIG_FILE")
  DASHBOARD_PORT=$(yq e '.project.dashboard.port' "$CONFIG_FILE")
  NODERED_USERNAME=$(yq e '.project.node_red_username' "$CONFIG_FILE")
  NODERED_PASSWORD_HASH=$(yq e '.project.node_red_password_hash' "$CONFIG_FILE")
  
  # Log parsed configuration
  log "Configuration loaded successfully:"
  log "Project Name: $PROJECT_NAME"
  log "Hostname: $HOSTNAME"
  log "WiFi SSID: $WIFI_SSID"
  log "STA WiFi SSID: $STA_WIFI_SSID"
  log "MQTT Port: $MQTT_PORT"
}

# Function to install dependencies
install_dependencies() {
  log "Updating package lists..."
  retry_with_backoff apt update

  log "Installing dependencies..."
  # Retry installation with error handling
  apt_install_with_retry() {
    local packages="$1"
    local attempts=3
    local attempt=1
    
    while (( attempt <= attempts )); do
      log "Installing packages (attempt $attempt/$attempts): $packages"
      
      if apt install -y $packages; then
        log "Installation successful!"
        return 0
      fi
      
      log "Installation failed. Cleaning up and retrying..."
      apt clean
      rm -f /var/lib/apt/lists/lock
      rm -f /var/cache/apt/archives/lock
      rm -f /var/lib/dpkg/lock*
      dpkg --configure -a
      
      attempt=$((attempt + 1))
      sleep 5
    done
    
    error_exit "Failed to install required packages after $attempts attempts"
  }
  
  # Base dependencies
  apt_install_with_retry "git wget curl dnsmasq hostapd python3-pip python3-venv mosquitto mosquitto-clients avahi-daemon build-essential net-tools"
  
  # Install Node.js if not already installed
  if ! command_exists node; then
    log "Installing Node.js..."
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt_install_with_retry "nodejs"
  fi

  log "Installing global npm packages..."
  if ! command_exists npm; then
    error_exit "npm not installed. Node.js installation may have failed."
  fi
  
  # Install Node-RED globally
  if ! command_exists node-red; then
    npm install -g --unsafe-perm node-red
  fi

  log "Setting up Python virtual environment..."
  python3 -m venv "$VENV_DIR"
  source "$VENV_DIR/bin/activate"
  pip install --upgrade pip
  pip install flask gunicorn paho-mqtt requests psutil pyyaml jinja2
  deactivate
}

# Function to set up WiFi AP+STA mode
setup_wifi() {
  log "Setting up WiFi in AP+STA mode..."
  
  # Create backup directory for network configs
  mkdir -p /etc/network/backups
  
  # Backup existing configurations
  if [ -f /etc/dhcpcd.conf ]; then
    cp /etc/dhcpcd.conf /etc/network/backups/dhcpcd.conf.bak-$(date +%Y%m%d%H%M%S)
  fi
  
  if [ -f /etc/hostapd/hostapd.conf ]; then
    cp /etc/hostapd/hostapd.conf /etc/network/backups/hostapd.conf.bak-$(date +%Y%m%d%H%M%S)
  fi
  
  if [ -f /etc/dnsmasq.conf ]; then
    cp /etc/dnsmasq.conf /etc/network/backups/dnsmasq.conf.bak-$(date +%Y%m%d%H%M%S)
  fi

  # Get network adapter name
  WIFI_ADAPTER=$(iw dev | grep Interface | awk '{print $2}' | head -n 1)
  if [ -z "$WIFI_ADAPTER" ]; then
    error_exit "No wireless adapter found"
  fi
  log "Using WiFi adapter: $WIFI_ADAPTER"

  # Install AP_STA_RPI_SAME_WIFI_CHIP
  AP_STA_DIR="/tmp/AP_STA_RPI_SAME_WIFI_CHIP"
  if [ -d "$AP_STA_DIR" ]; then
    rm -rf "$AP_STA_DIR"
  fi
  
  log "Cloning AP_STA_RPI_SAME_WIFI_CHIP repository..."
  retry_with_backoff git clone https://github.com/RaspAP/raspap-webgui /tmp/raspap-webgui
  
  # Extract just the AP+STA implementation
  mkdir -p "$AP_STA_DIR"
  cp /tmp/raspap-webgui/installers/ap-sta.sh "$AP_STA_DIR/"
  chmod +x "$AP_STA_DIR/ap-sta.sh"
  rm -rf /tmp/raspap-webgui
  
  # Generate configuration files from templates
  log "Generating WiFi configuration files..."
  
  # Generate dhcpcd.conf
  source "$VENV_DIR/bin/activate"
  python3 -c "
import jinja2, yaml, os
with open('$CONFIG_FILE', 'r') as f:
    config = yaml.safe_load(f)
with open('$TEMPLATES_DIR/dhcpcd.conf.j2', 'r') as f:
    template = jinja2.Template(f.read())
with open('/etc/dhcpcd.conf', 'w') as f:
    f.write(template.render(
        wifi_adapter='$WIFI_ADAPTER',
        project_name=config['project']['name']
    ))
"
  
  # Generate hostapd.conf
  python3 -c "
import jinja2, yaml, os
with open('$CONFIG_FILE', 'r') as f:
    config = yaml.safe_load(f)
with open('$TEMPLATES_DIR/hostapd.conf.j2', 'r') as f:
    template = jinja2.Template(f.read())
os.makedirs('/etc/hostapd', exist_ok=True)
with open('/etc/hostapd/hostapd.conf', 'w') as f:
    f.write(template.render(
        wifi_adapter='$WIFI_ADAPTER',
        wifi_ssid=config['project']['wifi_ssid'],
        wifi_password=config['project']['wifi_password']
    ))
"
  
  # Generate dnsmasq.conf
  python3 -c "
import jinja2, yaml, os
with open('$CONFIG_FILE', 'r') as f:
    config = yaml.safe_load(f)
with open('$TEMPLATES_DIR/dnsmasq.conf.j2', 'r') as f:
    template = jinja2.Template(f.read())
with open('/etc/dnsmasq.conf', 'w') as f:
    f.write(template.render(
        wifi_adapter='$WIFI_ADAPTER',
        project_name=config['project']['name'],
        hostname=config['project']['hostname'].split('.')[0]
    ))
"
  deactivate
  
  # Enable services
  log "Enabling hostapd and dnsmasq services..."
  systemctl unmask hostapd
  systemctl enable hostapd
  systemctl enable dnsmasq
  
  # Set hostname
  HOSTNAME_SHORT=$(echo "$HOSTNAME" | cut -d. -f1)
  echo "$HOSTNAME_SHORT" > /etc/hostname
  sed -i "s/127\.0\.1\.1.*/127.0.1.1\t$HOSTNAME_SHORT/g" /etc/hosts
  
  # Configure Avahi for .local domain
  log "Configuring Avahi for .local domain..."
  cat > /etc/avahi/avahi-daemon.conf << EOF
[server]
host-name=$HOSTNAME_SHORT
domain-name=local
use-ipv4=yes
use-ipv6=no
ratelimit-interval-usec=1000000
ratelimit-burst=1000

[wide-area]
enable-wide-area=yes

[publish]
publish-hinfo=no
publish-workstation=no

[reflector]
enable-reflector=no

[rlimits]
rlimit-core=0
rlimit-data=4194304
rlimit-fsize=0
rlimit-nofile=768
rlimit-stack=4194304
rlimit-nproc=3
EOF

  systemctl enable avahi-daemon
  
  # Set up wpa_supplicant for STA mode
  log "Setting up wpa_supplicant for STA mode..."
  cat > /etc/wpa_supplicant/wpa_supplicant-$WIFI_ADAPTER.conf << EOF
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
country=US

network={
    ssid="$STA_WIFI_SSID"
    psk="$STA_WIFI_PASSWORD"
    key_mgmt=WPA-PSK
    priority=1
}
EOF

  chmod 600 /etc/wpa_supplicant/wpa_supplicant-$WIFI_ADAPTER.conf
  
  # Configure coexistence via systemd-networkd
  log "Configuring network coexistence via systemd-networkd..."
  mkdir -p /etc/systemd/network/
  
  # Create network files
  cat > /etc/systemd/network/08-$WIFI_ADAPTER.network << EOF
[Match]
Name=$WIFI_ADAPTER

[Network]
DHCP=ipv4
MulticastDNS=yes

[DHCP]
RouteMetric=20
EOF

  # Enable systemd-networkd
  systemctl enable systemd-networkd
  
  log "WiFi setup completed"
}

# Function to set up Mosquitto MQTT broker
setup_mosquitto() {
  log "Setting up Mosquitto MQTT broker..."
  
  # Create password file
  touch /etc/mosquitto/passwd
  mosquitto_passwd -b /etc/mosquitto/passwd "$MQTT_USERNAME" "$MQTT_PASSWORD"
  
  # Generate configuration from template
  source "$VENV_DIR/bin/activate"
  python3 -c "
import jinja2, yaml
with open('$CONFIG_FILE', 'r') as f:
    config = yaml.safe_load(f)
with open('$TEMPLATES_DIR/mosquitto.conf.j2', 'r') as f:
    template = jinja2.Template(f.read())
with open('/etc/mosquitto/mosquitto.conf', 'w') as f:
    f.write(template.render(
        mqtt_port=config['project']['mqtt']['port']
    ))
"
  deactivate
  
  # Create a separate config file for password settings
  cat > /etc/mosquitto/conf.d/auth.conf << EOF
allow_anonymous false
password_file /etc/mosquitto/passwd
EOF

  # Ensure directories exist with proper permissions
  mkdir -p /var/lib/mosquitto
  chown mosquitto:mosquitto /var/lib/mosquitto
  
  # Enable and restart Mosquitto
  systemctl enable mosquitto
  systemctl restart mosquitto
  
  log "Testing Mosquitto configuration..."
  if ! pgrep mosquitto > /dev/null; then
    error_exit "Mosquitto failed to start. Check the logs with 'journalctl -u mosquitto'"
  fi
  
  log "Mosquitto MQTT broker setup completed"
}

# Function to set up VictoriaMetrics
setup_victoriametrics() {
  log "Setting up VictoriaMetrics time-series database..."
  
  # Download VictoriaMetrics
  VM_VERSION="v1.93.0"
  VM_DIR="/opt/victoria-metrics"
  VM_DATA="/var/lib/victoria-metrics"
  
  mkdir -p "$VM_DIR"
  mkdir -p "$VM_DATA"
  
  log "Downloading VictoriaMetrics..."
  if [ ! -f "$VM_DIR/victoria-metrics" ]; then
    retry_with_backoff wget -O /tmp/victoria-metrics.tar.gz https://github.com/VictoriaMetrics/VictoriaMetrics/releases/download/$VM_VERSION/victoria-metrics-arm-$VM_VERSION.tar.gz
    tar -xzf /tmp/victoria-metrics.tar.gz -C /tmp
    mv /tmp/victoria-metrics-arm-$VM_VERSION "$VM_DIR/victoria-metrics"
    chmod +x "$VM_DIR/victoria-metrics"
    rm /tmp/victoria-metrics.tar.gz
  fi
  
  # Generate configuration from template
  source "$VENV_DIR/bin/activate"
  python3 -c "
import jinja2, yaml
with open('$CONFIG_FILE', 'r') as f:
    config = yaml.safe_load(f)
with open('$TEMPLATES_DIR/victoria_metrics.yml.j2', 'r') as f:
    template = jinja2.Template(f.read())
with open('/etc/victoria-metrics.yml', 'w') as f:
    f.write(template.render(
        vm_port=config['project']['victoria_metrics']['port'],
        vm_data_dir='$VM_DATA'
    ))
"
  deactivate
  
  # Create systemd service
  cat > /etc/systemd/system/victoria-metrics.service << EOF
[Unit]
Description=VictoriaMetrics time series database
After=network.target

[Service]
Type=simple
User=root
ExecStart=$VM_DIR/victoria-metrics -httpListenAddr=:$VM_PORT -storageDataPath=$VM_DATA -retentionPeriod=1y
Restart=always
RestartSec=10
LimitNOFILE=65536
TimeoutStopSec=20
SendSIGKILL=no

[Install]
WantedBy=multi-user.target
EOF

  # Enable and start VictoriaMetrics
  systemctl daemon-reload
  systemctl enable victoria-metrics
  systemctl start victoria-metrics
  
  log "Testing VictoriaMetrics..."
  sleep 5
  
  if ! curl -s "http://localhost:$VM_PORT/health" | grep -q "VictoriaMetrics"; then
    error_exit "VictoriaMetrics failed to start. Check the logs with 'journalctl -u victoria-metrics'"
  fi
  
  log "VictoriaMetrics setup completed"
}

# Function to set up Node-RED
setup_nodered() {
  log "Setting up Node-RED..."
  
  # Ensure .node-red directory exists
  NODE_RED_DIR="/home/$SUDO_USER/.node-red"
  mkdir -p "$NODE_RED_DIR"
  
  # Install required Node-RED packages
  log "Installing Node-RED packages..."
  npm install -g --unsafe-perm node-red-admin
  
  # Set up admin user
  if [ ! -f "$NODE_RED_DIR/settings.js" ]; then
    # Copy default settings file
    mkdir -p "$NODE_RED_DIR"
    cp /usr/lib/node_modules/node-red/settings.js "$NODE_RED_DIR/settings.js"
  fi
  
  # Update settings.js to use the admin user/password
  cat > "$NODE_RED_DIR/settings.js" << EOF
module.exports = {
    uiPort: $NODERED_PORT,
    mqttReconnectTime: 15000,
    serialReconnectTime: 15000,
    debugMaxLength: 1000,
    functionGlobalContext: {},
    adminAuth: {
        type: "credentials",
        users: [{
            username: "$NODERED_USERNAME",
            password: "$NODERED_PASSWORD_HASH",
            permissions: "*"
        }]
    },
    httpNodeAuth: {
        user: "$NODERED_USERNAME",
        pass: "$NODERED_PASSWORD_HASH"
    },
    httpStaticAuth: {
        user: "$NODERED_USERNAME",
        pass: "$NODERED_PASSWORD_HASH"
    },
    editorTheme: {
        page: {
            title: "$PROJECT_NAME IoT Dashboard"
        },
        header: {
            title: "$PROJECT_NAME Node-RED"
        }
    },
    logging: {
        console: {
            level: "info",
            metrics: false,
            audit: false
        }
    },
    nodeMessageBufferMaxLength: 50,
    mqtt: {
        server: "localhost",
        port: $MQTT_PORT,
        clientid: "node-red",
        username: "$MQTT_USERNAME",
        password: "$MQTT_PASSWORD"
    }
};
EOF

  # Create a basic flow that subscribes to MQTT and sends to VictoriaMetrics
  cat > "$NODE_RED_DIR/flows.json" << EOF
[
    {
        "id": "mqtt-in",
        "type": "mqtt in",
        "name": "MQTT Telemetry",
        "topic": "$MQTT_TOPIC",
        "qos": "0",
        "datatype": "json",
        "broker": "mqtt-broker",
        "nl": false,
        "rap": true,
        "rh": 0,
        "inputs": 0,
        "x": 190,
        "y": 120,
        "wires": [
            [
                "process-telemetry"
            ]
        ]
    },
    {
        "id": "mqtt-broker",
        "type": "mqtt-broker",
        "name": "$PROJECT_NAME MQTT",
        "broker": "localhost",
        "port": "$MQTT_PORT",
        "clientid": "node-red-client",
        "usetls": false,
        "compatmode": false,
        "keepalive": "60",
        "cleansession": true,
        "birthTopic": "",
        "birthQos": "0",
        "birthPayload": "",
        "closeTopic": "",
        "closeQos": "0",
        "closePayload": "",
        "willTopic": "",
        "willQos": "0",
        "willPayload": "",
        "credentials": {
            "user": "$MQTT_USERNAME",
            "password": "$MQTT_PASSWORD"
        }
    },
    {
        "id": "process-telemetry",
        "type": "function",
        "name": "Process Telemetry",
        "func": "// Convert incoming JSON to InfluxDB line protocol format\\nconst msg = JSON.parse(msg.payload);\\nlet lines = [];\\n\\nObject.keys(msg).forEach(key => {\\n    if (typeof msg[key] === 'number') {\\n        lines.push(`telemetry,metric=${key} value=${msg[key]}`);\\n    }\\n});\\n\\nreturn { payload: lines.join('\\\\n') };",
        "outputs": 1,
        "noerr": 0,
        "initialize": "",
        "finalize": "",
        "libs": [],
        "x": 380,
        "y": 120,
        "wires": [
            [
                "victoria-metrics"
            ]
        ]
    },
    {
        "id": "victoria-metrics",
        "type": "http request",
        "name": "VictoriaMetrics",
        "method": "POST",
        "ret": "txt",
        "paytoqs": "ignore",
        "url": "http://localhost:$VM_PORT/write",
        "tls": "",
        "persist": false,
        "proxy": "",
        "authType": "",
        "x": 580,
        "y": 120,
        "wires": [
            [
                "debug"
            ]
        ]
    },
    {
        "id": "debug",
        "type": "debug",
        "name": "Debug",
        "active": true,
        "tosidebar": true,
        "console": false,
        "tostatus": false,
        "complete": "payload",
        "targetType": "msg",
        "statusVal": "",
        "statusType": "auto",
        "x": 770,
        "y": 120,
        "wires": []
    }
]
EOF

  # Install Node-RED packages
  log "Installing Node-RED MQTT packages..."
  cd "$NODE_RED_DIR"
  npm install node-red-contrib-mqtt-broker node-red-node-ui-table

  # Create systemd service for Node-RED
  cat > /etc/systemd/system/nodered.service << EOF
[Unit]
Description=Node-RED IoT Processing
After=network.target mosquitto.service

[Service]
Type=simple
User=$SUDO_USER
Group=$SUDO_USER
WorkingDirectory=/home/$SUDO_USER
Environment="NODE_OPTIONS=--max-old-space-size=256"
ExecStart=/usr/bin/node-red --settings /home/$SUDO_USER/.node-red/settings.js
Restart=always
RestartSec=10
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=nodered

[Install]
WantedBy=multi-user.target
EOF

  # Set permissions
  chown -R $SUDO_USER:$SUDO_USER "$NODE_RED_DIR"
  
  # Enable and start Node-RED
  systemctl daemon-reload
  systemctl enable nodered
  systemctl start nodered
  
  log "Node-RED setup completed"
}

# Function to set up Flask Dashboard
setup_flask_dashboard() {
  log "Setting up Flask Dashboard..."
  
  # Deploy Flask application from template
  source "$VENV_DIR/bin/activate"
  python3 -c "
import jinja2, yaml, os
with open('$CONFIG_FILE', 'r') as f:
    config = yaml.safe_load(f)
with open('$TEMPLATES_DIR/flask_app.py', 'r') as f:
    template = jinja2.Template(f.read())
with open('$PROJECT_DIR/flask_app_deployed.py', 'w') as f:
    f.write(template.render(
        project_name=config['project']['name'],
        mqtt_uri=config['project']['mqtt']['uri'],
        mqtt_port=config['project']['mqtt']['port'],
        mqtt_username=config['project']['mqtt']['username'],
        mqtt_password=config['project']['mqtt']['password'],
        mqtt_client_id=config['project']['mqtt']['client_id'],
        mqtt_topic=config['project']['mqtt']['topic'],
        vm_port=config['project']['victoria_metrics']['port']
    ))
"
  deactivate

  # Copy static files
  cp -r "$STATIC_DIR"/* "$PROJECT_DIR/static/"
  
  # Create systemd service for Flask
  cat > /etc/systemd/system/flask-dashboard.service << EOF
[Unit]
Description=Flask IoT Dashboard
After=network.target mosquitto.service victoria-metrics.service

[Service]
Type=simple
User=$SUDO_USER
Group=$SUDO_USER
WorkingDirectory=$PROJECT_DIR
ExecStart=$VENV_DIR/bin/gunicorn --workers 4 --bind 0.0.0.0:$DASHBOARD_PORT flask_app_deployed:app
Restart=always
RestartSec=10
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=flask-dashboard

[Install]
WantedBy=multi-user.target
EOF

  # Set permissions
  chown -R $SUDO_USER:$SUDO_USER "$PROJECT_DIR"
  
  # Enable and start Flask dashboard
  systemctl daemon-reload
  systemctl enable flask-dashboard
  systemctl start flask-dashboard
  
  log "Flask Dashboard setup completed"
}

# Function to perform complete setup
run_setup() {
  log "Starting complete setup..."
  
  # Create log file
  touch $LOG_FILE
  chown $SUDO_USER:$SUDO_USER $LOG_FILE
  
  # Load configuration
  load_config
  
  # Install dependencies
  install_dependencies
  
  # Set up components
  setup_wifi
  setup_mosquitto
  setup_victoriametrics
  setup_nodered
  setup_flask_dashboard
  
  # Final system restart message
  log "Setup completed successfully! The system will now reboot."
  log "After reboot, connect to the WiFi network: $WIFI_SSID"
  log "Then access the dashboard at: http://$HOSTNAME:$DASHBOARD_PORT"
  
  # Reboot
  reboot
}

# Function to update the system
run_update() {
  log "Starting system update..."
  
  # Load configuration
  load_config
  
  # Update components without full reinstall
  systemctl stop flask-dashboard nodered victoria-metrics mosquitto
  
  # Update Flask app
  setup_flask_dashboard
  
  # Update Node-RED flows
  setup_nodered
  
  # Restart services
  systemctl start mosquitto victoria-metrics nodered flask-dashboard
  
  log "Update completed successfully!"
}

# Function to create backup
run_backup() {
  log "Creating system backup..."
  
  # Load configuration
  load_config
  
  # Create backup timestamp
  BACKUP_TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
  BACKUP_FILE="$BACKUP_DIR/${PROJECT_NAME}_backup_$BACKUP_TIMESTAMP.tar.gz"
  
  # Create backup directory
  mkdir -p "$BACKUP_DIR"
  
  # Create temporary backup directory
  TEMP_BACKUP_DIR="/tmp/syhub_backup_$BACKUP_TIMESTAMP"
  mkdir -p "$TEMP_BACKUP_DIR"
  
  # Copy configuration files
  cp -r "$PROJECT_DIR/config" "$TEMP_BACKUP_DIR/"
  cp -r "$PROJECT_DIR/scripts" "$TEMP_BACKUP_DIR/"
  cp -r "$PROJECT_DIR/templates" "$TEMP_BACKUP_DIR/"
  cp -r "$PROJECT_DIR/static" "$TEMP_BACKUP_DIR/"
  
  # Backup Node-RED flows
  if [ -f "/home/$SUDO_USER/.node-red/flows.json" ]; then
    mkdir -p "$TEMP_BACKUP_DIR/node-red"
    cp "/home/$SUDO_USER/.node-red/flows.json" "$TEMP_BACKUP_DIR/node-red/"
  fi
  
  # Backup VictoriaMetrics data (latest snapshot)
  if [ -d "/var/lib/victoria-metrics" ]; then
    mkdir -p "$TEMP_BACKUP_DIR/victoria-metrics"
    find /var/lib/victoria-metrics -type f -name "*.bin" -mtime -1 -exec cp {} "$TEMP_BACKUP_DIR/victoria-metrics/" \;
  fi
  
  # Create compressed archive
  tar -czf "$BACKUP_FILE" -C "$(dirname "$TEMP_BACKUP_DIR")" "$(basename "$TEMP_BACKUP_DIR")"
  
  # Remove temporary directory
  rm -rf "$TEMP_