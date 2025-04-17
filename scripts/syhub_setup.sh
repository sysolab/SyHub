#!/bin/bash

# syhub.sh: Setup script for IoT monitoring system on Raspberry Pi
# Manages WiFi AP+STA, Mosquitto, VictoriaMetrics, Node-RED, and Flask dashboard

# Function to check if script is run as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "This script must be run as root. Use sudo."
        exit 1
    fi
}

# Function to load configuration from config.yml
load_config() {
    if ! command -v yq &> /dev/null; then
        echo "Installing yq for YAML parsing..."
        sudo apt update
        sudo apt install -y yq || { echo "Failed to install yq"; exit 1; }
    fi

    CONFIG_FILE="$HOME/syhub/config/config.yml"
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "Config file $CONFIG_FILE not found!"
        exit 1
    fi

    PROJECT_NAME=$(yq e '.project.name' "$CONFIG_FILE")
    WIFI_SSID=$(yq e '.project.wifi_ssid' "$CONFIG_FILE")
    WIFI_PASSWORD=$(yq e '.project.wifi_password' "$CONFIG_FILE")
    STA_WIFI_SSID=$(yq e '.project.sta_wifi_ssid' "$CONFIG_FILE")
    STA_WIFI_PASSWORD=$(yq e '.project.sta_wifi_password' "$CONFIG_FILE")
    MQTT_USERNAME=$(yq e '.project.mqtt.username' "$CONFIG_FILE")
    MQTT_PASSWORD=$(yq e '.project.mqtt.password' "$CONFIG_FILE")
    MQTT_PORT=$(yq e '.project.mqtt.port' "$CONFIG_FILE")
    MQTT_TOPIC=$(yq e '.project.mqtt.topic' "$CONFIG_FILE")
    VM_PORT=$(yq e '.project.victoria_metrics.port' "$CONFIG_FILE")
    NR_PORT=$(yq e '.project.node_red.port' "$CONFIG_FILE")
    DASHBOARD_PORT=$(yq e '.project.dashboard.port' "$CONFIG_FILE")
    NR_USERNAME=$(yq e '.project.node_red_username' "$CONFIG_FILE")
    NR_PASSWORD_HASH=$(yq e '.project.node_red_password_hash' "$CONFIG_FILE")

    # Validate STA WiFi settings
    if [ -z "$STA_WIFI_SSID" ] || [ -z "$STA_WIFI_PASSWORD" ]; then
        echo "Error: sta_wifi_ssid and sta_wifi_password must be set in $CONFIG_FILE"
        exit 1
    fi
}

# Function to set up WiFi Access Point + Station
setup_wifi_ap() {
    echo "Setting up WiFi AP+STA using AP_STA_RPI_SAME_WIFI_CHIP..."
    sudo apt update
    sudo apt install -y git hostapd dnsmasq avahi-daemon wpasupplicant || { echo "Failed to install WiFi dependencies"; exit 1; }

    # Verify dnsmasq service exists
    if ! systemctl list-units --full -all | grep -q "dnsmasq.service"; then
        echo "dnsmasq service not found, reinstalling..."
        sudo apt install --reinstall -y dnsmasq || { echo "Failed to reinstall dnsmasq"; exit 1; }
    fi

    # Clone AP_STA_RPI_SAME_WIFI_CHIP repository
    if [ ! -d "/tmp/AP_STA_RPI_SAME_WIFI_CHIP" ]; then
        git clone https://github.com/MkLHX/AP_STA_RPI_SAME_WIFI_CHIP.git /tmp/AP_STA_RPI_SAME_WIFI_CHIP || { echo "Failed to clone AP_STA_RPI_SAME_WIFI_CHIP"; exit 1; }
    fi

    # Configure AP mode (hostapd)
    envsubst < $HOME/syhub/templates/hostapd.conf.j2 > /tmp/AP_STA_RPI_SAME_WIFI_CHIP/config/hostapd.conf
    envsubst < $HOME/syhub/templates/dnsmasq.conf.j2 > /tmp/AP_STA_RPI_SAME_WIFI_CHIP/config/dnsmasq.conf
    envsubst < $HOME/syhub/templates/dhcpcd.conf.j2 > /etc/dhcpcd.conf

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
    sudo apt install -y mosquitto mosquitto-clients || { echo "Failed to install Mosquitto"; exit 1; }

    # Configure Mosquitto
    envsubst < $HOME/syhub/templates/mosquitto.conf.j2 > /etc/mosquitto/mosquitto.conf
    sudo chmod 644 /etc/mosquitto/mosquitto.conf
    sudo mosquitto_passwd -c /etc/mosquitto/passwd "$MQTT_USERNAME" <<< "$MQTT_PASSWORD"
    sudo chmod 600 /etc/mosquitto/passwd

    sudo systemctl enable mosquitto
    sudo systemctl start mosquitto || { echo "Failed to start Mosquitto; check 'journalctl -xeu mosquitto.service'"; exit 1; }
}

# Function to install VictoriaMetrics
install_victoria_metrics() {
    echo "Installing VictoriaMetrics..."
    if [ ! -f "/usr/local/bin/victoria-metrics" ]; then
        wget https://github.com/VictoriaMetrics/VictoriaMetrics/releases/download/v1.92.0/victoria-metrics-linux-arm.tar.gz || { echo "Failed to download VictoriaMetrics"; exit 1; }
        tar -xzf victoria-metrics-linux-arm.tar.gz
        sudo mv victoria-metrics-linux-arm/victoria-metrics /usr/local/bin/
        rm -rf victoria-metrics-linux-arm*
    fi

    # Configure VictoriaMetrics
    envsubst < $HOME/syhub/templates/victoria_metrics.yml.j2 > /etc/victoriametrics.yml
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

    sudo systemctl enable victoriametrics
    sudo systemctl start victoriametrics || { echo "Failed to start VictoriaMetrics"; exit 1; }
}

# Function to install Node-RED
install_node_red() {
    echo "Installing Node-RED..."
    sudo apt install -y nodejs npm || { echo "Failed to install Node.js and npm"; exit 1; }
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
    sudo apt install -y python3-pip || { echo "Failed to install pip"; exit 1; }
    pip3 install flask gunicorn paho-mqtt requests psutil || { echo "Failed to install Python packages"; exit 1; }

    # Deploy Flask app
    cp $HOME/syhub/templates/flask_app.py $HOME/syhub/flask_app_deployed.py
    sudo chmod 644 $HOME/syhub/flask_app_deployed.py

    # Create systemd service
    cat << EOF > /etc/systemd/system/flask-dashboard.service
[Unit]
Description=Flask Dashboard
After=network.target

[Service]
User=pi
WorkingDirectory=$HOME/syhub
ExecStart=/usr/local/bin/gunicorn -w 4 -b 0.0.0.0:$DASHBOARD_PORT flask_app_deployed:app
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl enable flask-dashboard
    sudo systemctl start flask-dashboard || { echo "Failed to start Flask dashboard"; exit 1; }
}

# Function to check status
status() {
    echo "Checking system status..."
    sudo systemctl status hostapd
    sudo systemctl status dnsmasq
    sudo systemctl status avahi-daemon
    sudo systemctl status mosquitto
    sudo systemctl status victoriametrics
    sudo systemctl status nodered
    sudo systemctl status flask-dashboard
}

# Main setup function
setup() {
    check_root
    load_config
    setup_wifi_ap &
    install_mosquitto &
    install_victoria_metrics &
    install_node_red &
    install_dashboard &
    wait
    echo "Setup complete! Reboot recommended."
    read -p "Reboot now? [Y/n]: " reboot
    if [[ "$reboot" != "n" && "$reboot" != "N" ]]; then
        sudo reboot
    fi
}

# Function to update system
update() {
    echo "Updating system..."
    sudo apt update
    sudo apt upgrade -y
    pip3 install --upgrade flask gunicorn paho-mqtt requests psutil
    sudo npm install -g --unsafe-perm node-red@latest
    sudo npm audit fix -g
}

# Function to purge system
purge() {
    echo "Purging system..."
    sudo systemctl stop hostapd dnsmasq avahi-daemon mosquitto victoriametrics nodered flask-dashboard
    sudo systemctl disable hostapd dnsmasq avahi-daemon mosquitto victoriametrics nodered flask-dashboard
    sudo apt remove -y hostapd dnsmasq avahi-daemon mosquitto mosquitto-clients nodejs npm python3-pip wpasupplicant
    sudo rm -rf /usr/local/bin/victoria-metrics /etc/victoriametrics.yml /var/lib/victoria-metrics
    sudo rm -rf /home/pi/.node-red
    sudo rm -f /etc/systemd/system/flask-dashboard.service
}

# Function to backup system
backup() {
    echo "Backing up system..."
    tar -czf $HOME/syhub_backup_$(date +%F).tar.gz $HOME/syhub
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