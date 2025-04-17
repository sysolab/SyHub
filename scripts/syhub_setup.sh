```bash
#!/bin/bash

# syhub.sh: Setup script for IoT monitoring system on Raspberry Pi
# Version: 1.3.0
# Manages WiFi AP+STA, Mosquitto, VictoriaMetrics, Node-RED, and Flask dashboard
# Log file: /tmp/syhub_setup.log

# Initialize logging
LOG_FILE="/tmp/syhub_setup.log"
exec 1>>"$LOG_FILE" 2>&1
echo "Starting syhub.sh setup at $(date)"

# Function to check if script is run as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "This script must be run as root. Use sudo."
        exit 1
    fi
}

# Function to set user home directory
set_user_home() {
    if [ -n "$SUDO_USER" ]; then
        USER_HOME="/home/$SUDO_USER"
    else
        USER_HOME="$HOME"
    fi
    if [ ! -d "$USER_HOME" ]; then
        echo "User home directory $USER_HOME not found!"
        exit 1
    fi
}

# Function to handle apt locks
wait_for_apt() {
    local timeout=300
    local elapsed=0
    echo "Checking for apt locks..."
    while [ $elapsed -lt $timeout ]; do
        if ! pgrep -x "apt" > /dev/null && ! lsof /var/lib/dpkg/lock-frontend > /dev/null 2>&1; then
            echo "No apt locks detected."
            return 0
        fi
        echo "Waiting for apt lock to clear..."
        sleep 5
        elapsed=$((elapsed + 5))
    done
    echo "Timeout waiting for apt lock. Attempting to clear stale locks..."
    sudo killall apt apt-get 2>/dev/null || true
    sudo rm -f /var/lib/dpkg/lock-frontend /var/cache/apt/archives/lock
    sudo dpkg --configure -a
    echo "Apt locks cleared."
}

# Function to install and verify yq
install_yq() {
    echo "Checking for yq..."
    if ! command -v yq &> /dev/null || ! yq --version | grep -q "mikefarah/yq"; then
        echo "Installing yq (version 4.35.2)..."
        wait_for_apt
        sudo apt update
        for attempt in {1..3}; do
            wget https://github.com/mikefarah/yq/releases/download/v4.45.1/yq_linux_arm64 -O /usr/local/bin/yq && break
            echo "Retry $attempt: Failed to download yq"
            sleep 5
        done || { echo "Failed to download yq after retries"; exit 1; }
        sudo chmod +x /usr/local/bin/yq
    fi
    YQ_VERSION=$(yq --version | awk '{print $NF}')
    echo "Detected yq version: $YQ_VERSION"
    if [[ ! "$YQ_VERSION" =~ ^v?4\.[0-9]+\.[0-9]+ ]]; then
        echo "Error: yq version $YQ_VERSION is not supported. Requires version 4.x."
        exit 1
    fi
}

# Function to load configuration from config.yml
load_config() {
    install_yq
    CONFIG_FILE="$USER_HOME/syhub/config/config.yml"
    echo "Loading configuration from $CONFIG_FILE..."
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "Config file $CONFIG_FILE not found!"
        exit 1
    fi

    # Validate YAML syntax
    echo "Validating YAML syntax..."
    if ! yq e '.' "$CONFIG_FILE" > /tmp/config.yml.parsed 2> /tmp/config.yml.errors; then
        echo "Error: $CONFIG_FILE contains invalid YAML"
        cat /tmp/config.yml.errors
        exit 1
    fi
    echo "Parsed YAML structure:"
    cat /tmp/config.yml.parsed

    # Load configuration with error checking
    load_field() {
        local field=$1
        local var_name=$2
        local value
        value=$(yq e "$field" "$CONFIG_FILE")
        if [ $? -ne 0 ] || [ "$value" = "null" ] || [ -z "$value" ]; then
            echo "Error: Failed to parse $field from $CONFIG_FILE"
            return 1
        fi
        eval "$var_name='$value'"
    }

    load_field '.project.name' PROJECT_NAME || exit 1
    load_field '.project.wifi_ssid' WIFI_SSID || exit 1
    load_field '.project.wifi_password' WIFI_PASSWORD || exit 1
    load_field '.project.sta_wifi_ssid' STA_WIFI_SSID || exit 1
    load_field '.project.sta_wifi_password' STA_WIFI_PASSWORD || exit 1
    load_field '.project.mqtt.username' MQTT_USERNAME || exit 1
    load_field '.project.mqtt.password' MQTT_PASSWORD || exit 1
    load_field '.project.mqtt.port' MQTT_PORT || exit 1
    load_field '.project.mqtt.topic' MQTT_TOPIC || exit 1
    load_field '.project.victoria_metrics.port' VM_PORT || exit 1
    load_field '.project.node_red.port' NR_PORT || exit 1
    load_field '.project.dashboard.port' DASHBOARD_PORT || exit 1
    load_field '.project.node_red_username' NR_USERNAME || exit 1
    load_field '.project.node_red_password_hash' NR_PASSWORD_HASH || exit 1

    # Validate required fields
    if [ -z "$PROJECT_NAME" ] || [ -z "$WIFI_SSID" ] || [ -z "$WIFI_PASSWORD" ] || \
       [ -z "$STA_WIFI_SSID" ] || [ -z "$STA_WIFI_PASSWORD" ] || \
       [ -z "$MQTT_USERNAME" ] || [ -z "$MQTT_PASSWORD" ] || [ -z "$MQTT_PORT" ] || \
       [ -z "$MQTT_TOPIC" ] || [ -z "$VM_PORT" ] || [ -z "$NR_PORT" ] || \
       [ -z "$DASHBOARD_PORT" ] || [ -z "$NR_USERNAME" ] || [ -z "$NR_PASSWORD_HASH" ]; then
        echo "Error: One or more required fields are missing or invalid in $CONFIG_FILE"
        echo "Please verify the following fields in $CONFIG_FILE:"
        echo "- project.name"
        echo "- project.wifi_ssid"
        echo "- project.wifi_password"
        echo "- project.sta_wifi_ssid"
        echo "- project.sta_wifi_password"
        echo "- project.mqtt.username"
        echo "- project.mqtt.password"
        echo "- project.mqtt.port"
        echo "- project.mqtt.topic"
        echo "- project.victoria_metrics.port"
        echo "- project.node_red.port"
        echo "- project.dashboard.port"
        echo "- project.node_red_username"
        echo "- project.node_red_password_hash"
        exit 1
    fi
}

# Function to set up WiFi Access Point + Station
setup_wifi_ap() {
    echo "Setting up WiFi AP+STA using AP_STA_RPI_SAME_WIFI_CHIP..."
    wait_for_apt
    sudo DEBIAN_FRONTEND=noninteractive apt update
    if [ -f /etc/dnsmasq.conf ]; then
        echo "Backing up existing /etc/dnsmasq.conf..."
        sudo mv /etc/dnsmasq.conf /etc/dnsmasq.conf.bak-$(date +%F)
    fi
    sudo DEBIAN_FRONTEND=noninteractive apt install -y git hostapd dnsmasq avahi-daemon wpasupplicant || { echo "Failed to install WiFi dependencies"; exit 1; }

    # Clone AP_STA_RPI_SAME_WIFI_CHIP repository
    if [ ! -d "/tmp/AP_STA_RPI_SAME_WIFI_CHIP" ]; then
        for attempt in {1..3}; do
            git clone https://github.com/MkLHX/AP_STA_RPI_SAME_WIFI_CHIP.git /tmp/AP_STA_RPI_SAME_WIFI_CHIP && break
            echo "Retry $attempt: Failed to clone AP_STA_RPI_SAME_WIFI_CHIP"
            sleep 5
        done || { echo "Failed to clone AP_STA_RPI_SAME_WIFI_CHIP after retries"; exit 1; }
    fi

    # Configure AP mode (hostapd)
    envsubst < "$USER_HOME/syhub/templates/hostapd.conf.j2" > /tmp/AP_STA_RPI_SAME_WIFI_CHIP/config/hostapd.conf
    envsubst < "$USER_HOME/syhub/templates/dnsmasq.conf.j2" > /tmp/AP_STA_RPI_SAME_WIFI_CHIP/config/dnsmasq.conf
    envsubst < "$USER_HOME/syhub/templates/dhcpcd.conf.j2" > /etc/dhcpcd.conf

    # Configure STA mode (wpa_supplicant)
    cat << EOF > /tmp/AP_STA_RPI_SAME_WIFI_CHIP/config/wpa_supplicant.conf
ctrl_interface=DIR=/var/run/ WPA_GROUP=netdev
update_config=1
country=US

network={
    ssid="$STA_WIFI_SSID"
    psk="$STA_WIFI_PASSWORD"
}
EOF

    # Run the AP+STA setup script
    cd /tmp/AP_STA_RPI_SAME_WIFI_CHIP
    sudo bash install.sh || { echo "WiFi AP+STA setup failed"; exit 1; }

    # Enable and start services
    sudo systemctl unmask hostapd
    sudo systemctl enable hostapd dnsmasq avahi-daemon
    sudo systemctl start hostapd dnsmasq avahi-daemon || { echo "Failed to start WiFi services"; exit 1; }
}

# Function to install Mosquitto
install_mosquitto() {
    echo "Installing Mosquitto MQTT Broker..."
    wait_for_apt
    sudo DEBIAN_FRONTEND=noninteractive apt install -y mosquitto mosquitto-clients || { echo "Failed to install Mosquitto"; exit 1; }

    # Configure Mosquitto
    envsubst < "$USER_HOME/syhub/templates/mosquitto.conf.j2" > /etc/mosquitto/mosquitto.conf
    sudo chmod 644 /etc/mosquitto/mosquitto.conf
    echo "$MQTT_USERNAME:$MQTT_PASSWORD" | sudo tee /etc/mosquitto/passwd > /dev/null
    sudo mosquitto_passwd -U /etc/mosquitto/passwd
    sudo chmod 600 /etc/mosquitto/passwd

    sudo systemctl enable mosquitto
    sudo systemctl start mosquitto || { echo "Failed to start Mosquitto; check 'journalctl -xeu mosquitto.service'"; exit 1; }
}

# Function to install VictoriaMetrics
install_victoria_metrics() {
    echo "Installing VictoriaMetrics..."
    if [ ! -f "/usr/local/bin/victoria-metrics" ]; then
        for attempt in {1..3}; do
            wget https://github.com/VictoriaMetrics/VictoriaMetrics/releases/download/v1.115.0/victoria-metrics-linux-arm64-v1.115.0.tar.gz -O /tmp/vm.tar.gz && break
            echo "Retry $attempt: Failed to download VictoriaMetrics"
            sleep 5
        done || { echo "Failed to download VictoriaMetrics after retries"; exit 1; }
        sudo tar -xzf /tmp/vm.tar.gz -C /usr/local/bin
        sudo rm /tmp/vm.tar.gz
    fi

    # Configure VictoriaMetrics
    envsubst < "$USER_HOME/syhub/templates/victoria_metrics.yml.j2" > /etc/victoriametrics.yml
    sudo chmod 644 /etc/victoriametrics.yml

    # Create systemd service
    cat << EOF > /etc/systemd/system/victoriametrics.service
[Unit]
Description=VictoriaMetrics Time-Series Database
After=network.target

[Service]
ExecStart=/usr/local/bin/victoria-metrics -httpListenAddr=:$VM_PORT -storageDataPath=/var/lib/victoria-metrics
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable victoriametrics
    sudo systemctl start victoriametrics || { echo "Failed to start VictoriaMetrics"; exit 1; }
}

# Function to install Node-RED
install_node_red() {
    echo "Installing Node-RED..."
    wait_for_apt
    sudo DEBIAN_FRONTEND=noninteractive apt install -y nodejs npm || { echo "Failed to install Node.js and npm"; exit 1; }
    sudo npm install -g --unsafe-perm node-red@latest || { echo "Failed to install Node-RED"; exit 1; }
    sudo npm audit fix -g || echo "Some Node-RED vulnerabilities could not be fixed automatically; run 'npm audit' for details."

    # Configure Node-RED
    sudo mkdir -p /home/pi/.node-red
    sudo chown pi:pi /home/pi/.node-red
    cat << EOF > /home/pi/.node-red/settings.js
module.exports = {
    flowFile: 'flows.json',
    adminAuth: {
        type: "credentials",
        users: [{
            username: "$NR_USERNAME",
            password: "$NR_PASSWORD_HASH",
            permissions: "*"
        }]
    },
    httpAdminRoot: "/admin",
    httpNodeRoot: "/",
    userDir: "/home/pi/.node-red/",
    nodesDir: "/home/pi/.node-red/nodes",
    uiPort: $NR_PORT,
    functionGlobalContext: { },
    editorTheme: {
        projects: {
            enabled: false
        }
    },
    memory: {
        maxOldSpaceSize: 256
    }
}
EOF

    # Create a minimal flow
    cat << EOF > /home/pi/.node-red/flows.json
[
    {
        "id": "mqtt-in",
        "type": "mqtt in",
        "name": "MQTT Input",
        "topic": "$MQTT_TOPIC",
        "broker": "mqtt-broker",
        "x": 100,
        "y": 100,
        "wires": [["http-request"]]
    },
    {
        "id": "http-request",
        "type": "http request",
        "name": "Send to VictoriaMetrics",
        "method": "POST",
        "url": "http://localhost:$VM_PORT/write",
        "x": 300,
        "y": 100,
        "wires": []
    },
    {
        "id": "mqtt-broker",
        "type": "mqtt-broker",
        "name": "Local MQTT",
        "broker": "localhost",
        "port": "$MQTT_PORT",
        "clientid": "",
        "usetls": false,
        "protocolVersion": "4",
        "credentials": {
            "user": "$MQTT_USERNAME",
            "password": "$MQTT_PASSWORD"
        }
    }
]
EOF

    sudo chown pi:pi /home/pi/.node-red/*
    sudo systemctl enable nodered
    sudo systemctl start nodered || { echo "Failed to start Node-RED"; exit 1; }
}

# Function to install Flask Dashboard
install_dashboard() {
    echo "Installing Flask Dashboard..."
    wait_for_apt
    sudo DEBIAN_FRONTEND=noninteractive apt install -y python3-pip python3-venv || { echo "Failed to install pip and venv"; exit 1; }

    # Create and activate virtual environment
    VENV_DIR="$USER_HOME/syhub/venv"
    if [ ! -d "$VENV_DIR" ]; then
        python3 -m venv "$VENV_DIR"
    fi
    source "$VENV_DIR/bin/activate"
    pip install flask gunicorn paho-mqtt requests psutil || { echo "Failed to install Python packages"; deactivate; exit 1; }
    deactivate

    # Deploy Flask app
    cp "$USER_HOME/syhub/templates/flask_app.py" "$USER_HOME/syhub/flask_app_deployed.py"
    sudo chmod 644 "$USER_HOME/syhub/flask_app_deployed.py"

    # Create systemd service
    cat << EOF > /etc/systemd/system/flask-dashboard.service
[Unit]
Description=Flask Dashboard
After=network.target

[Service]
User=pi
WorkingDirectory=$USER_HOME/syhub
ExecStart=$VENV_DIR/bin/gunicorn -w 4 -b 0.0.0.0:$DASHBOARD_PORT flask_app_deployed:app
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable flask-dashboard
    sudo systemctl start flask-dashboard || { echo "Failed to start Flask dashboard"; exit 1; }
}

# Function to check status
status() {
    echo "Checking system status..."
    for service in hostapd dnsmasq avahi-daemon mosquitto victoriametrics nodered flask-dashboard; do
        sudo systemctl status "$service" --no-pager || true
    done
}

# Main setup function
setup() {
    check_root
    set_user_home
    load_config
    echo "Starting sequential setup..."
    setup_wifi_ap
    install_mosquitto
    install_victoria_metrics
    install_node_red
    install_dashboard
    echo "Setup complete! Reboot recommended."
    read -p "Reboot now? [Y/n]: " reboot
    if [[ "$reboot" != "n" && "$reboot" != "N" ]]; then
        sudo reboot
    fi
}

# Function to update system
update() {
    set_user_home
    echo "Updating system..."
    wait_for_apt
    sudo DEBIAN_FRONTEND=noninteractive apt update
    sudo DEBIAN_FRONTEND=noninteractive apt upgrade -y
    VENV_DIR="$USER_HOME/syhub/venv"
    if [ -d "$VENV_DIR" ]; then
        source "$VENV_DIR/bin/activate"
        pip install --upgrade flask gunicorn paho-mqtt requests psutil
        deactivate
    fi
    sudo npm install -g --unsafe-perm node-red@latest
    sudo npm audit fix -g
    sudo systemctl restart mosquitto victoriametrics nodered flask-dashboard
}

# Function to purge system
purge() {
    set_user_home
    echo "Purging system..."
    sudo systemctl stop hostapd dnsmasq avahi-daemon mosquitto victoriametrics nodered flask-dashboard 2>/dev/null || true
    sudo systemctl disable hostapd dnsmasq avahi-daemon mosquitto victoriametrics nodered flask-dashboard 2>/dev/null || true
    wait_for_apt
    sudo DEBIAN_FRONTEND=noninteractive apt remove -y --purge hostapd dnsmasq avahi-daemon mosquitto mosquitto-clients nodejs npm python3-pip python3-venv wpasupplicant
    sudo DEBIAN_FRONTEND=noninteractive apt autoremove -y
    sudo rm -rf /usr/local/bin/victoria-metrics /etc/victoriametrics.yml /var/lib/victoria-metrics
    sudo rm -rf /home/pi/.node-red
    sudo rm -rf "$USER_HOME/syhub/venv"
    sudo rm -f /etc/systemd/system/flask-dashboard.service
    sudo rm -f /etc/mosquitto/mosquitto.conf /etc/mosquitto/passwd
    sudo rm -rf /tmp/AP_STA_RPI_SAME_WIFI_CHIP
}

# Function to backup system
backup() {
    set_user_home
    echo "Backing up system..."
    timestamp=$(date +%Y%m%d_%H%M%S)
    mkdir -p "$USER_HOME/backups"
    tar -czf "$USER_HOME/backups/syhub_backup_$timestamp.tar.gz" "$USER_HOME/syhub"
    echo "Backup created at $USER_HOME/backups/syhub_backup_$timestamp.tar.gz"
}

# Main script logic
case "$1" in
    setup)
        setup
        ;;
    update)
        update
        ;;
    purge)
        purge
        ;;
    backup)
        backup
        ;;
    status)
        status
        ;;
    *)
        echo "Usage: $0 {setup|update|purge|backup|status}"
        exit 1
        ;;
esac

echo "Script completed at $(date)"
```