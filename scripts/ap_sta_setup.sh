#!/bin/bash

# ap_sta_setup.sh - Setup Access Point + Station Mode on Raspberry Pi
# Based on https://github.com/MkLHX/AP_STA_RPI_SAME_WIFI_CHIP
# 
# This script enables simultaneous AP (Access Point) and STA (Station) modes
# on the same WiFi chip for Raspberry Pi

# Ensure script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run with sudo"
    exit 1
fi

# Logging function
log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1"
}

# Function to install required packages
install_required_packages() {
    log "Installing required packages..."
    apt update
    apt install -y hostapd dnsmasq dhcpcd5 iptables
}

# Configure AP+STA mode
setup_ap_sta_mode() {
    local ssid=$1
    local wpa_passphrase=$2
    local ap_ssid=$3
    local ap_passphrase=$4
    local interface=${5:-wlan0}
    
    log "Setting up AP+STA mode..."
    log "  STA SSID: $ssid"
    log "  AP SSID: $ap_ssid"
    log "  Interface: $interface"
    
    # Back up existing configuration files
    log "Backing up existing configurations..."
    cp /etc/dhcpcd.conf /etc/dhcpcd.conf.bak || true
    cp /etc/dnsmasq.conf /etc/dnsmasq.conf.bak || true
    cp /etc/hostapd/hostapd.conf /etc/hostapd/hostapd.conf.bak || true
    cp /etc/sysctl.conf /etc/sysctl.conf.bak || true
    cp /etc/default/hostapd /etc/default/hostapd.bak || true
    
    # Configure dhcpcd
    log "Configuring dhcpcd..."
    cat > /etc/dhcpcd.conf << EOL
interface ${interface}
    static ip_address=192.168.4.1/24
    nohook wpa_supplicant
EOL
    
    # Configure dnsmasq
    log "Configuring dnsmasq..."
    cat > /etc/dnsmasq.conf << EOL
interface=${interface}
dhcp-range=192.168.4.2,192.168.4.20,255.255.255.0,24h
domain=local
address=/sysohub.local/192.168.4.1
EOL
    
    # Configure hostapd
    log "Configuring hostapd..."
    mkdir -p /etc/hostapd
    cat > /etc/hostapd/hostapd.conf << EOL
interface=${interface}
driver=nl80211
ssid=${ap_ssid}
hw_mode=g
channel=7
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=${ap_passphrase}
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP
EOL
    
    # Configure hostapd default file
    log "Configuring hostapd defaults..."
    cat > /etc/default/hostapd << EOL
DAEMON_CONF="/etc/hostapd/hostapd.conf"
EOL
    
    # Enable IP forwarding for routing
    log "Enabling IP forwarding..."
    echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-sysohub.conf
    sysctl -w net.ipv4.ip_forward=1
    
    # Create WPA supplicant configuration for station mode
    log "Configuring WPA supplicant for station mode..."
    cat > /etc/wpa_supplicant/wpa_supplicant-${interface}.conf << EOL
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
country=US

network={
    ssid="${ssid}"
    psk="${wpa_passphrase}"
    key_mgmt=WPA-PSK
    priority=1
}
EOL
    chmod 600 /etc/wpa_supplicant/wpa_supplicant-${interface}.conf
    
    # Create systemd service for WPA supplicant
    log "Creating systemd service for WPA supplicant..."
    cat > /etc/systemd/system/wpa_supplicant@${interface}.service << EOL
[Unit]
Description=WPA supplicant daemon (interface-specific version)
Requires=sys-subsystem-net-devices-%i.device
After=sys-subsystem-net-devices-%i.device
Before=network.target
Wants=network.target

[Service]
Type=simple
ExecStart=/sbin/wpa_supplicant -c/etc/wpa_supplicant/wpa_supplicant-%I.conf -i%I
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOL
    
    # Create iptables script for NAT
    log "Creating iptables script for NAT..."
    cat > /etc/iptables.ipv4.nat << EOL
*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
-A FORWARD -i ${interface} -o ${interface} -m state --state RELATED,ESTABLISHED -j ACCEPT
-A FORWARD -i ${interface} -o ${interface} -j ACCEPT
COMMIT

*nat
:PREROUTING ACCEPT [0:0]
:INPUT ACCEPT [0:0] 
:OUTPUT ACCEPT [0:0]
:POSTROUTING ACCEPT [0:0]
-A POSTROUTING -o ${interface} -j MASQUERADE
COMMIT
EOL
    
    # Create systemd service for iptables
    log "Creating systemd service for iptables..."
    cat > /etc/systemd/system/iptables-restore.service << EOL
[Unit]
Description=Restore iptables firewall rules
Before=network-pre.target

[Service]
Type=oneshot
ExecStart=/sbin/iptables-restore /etc/iptables.ipv4.nat
ExecReload=/sbin/iptables-restore /etc/iptables.ipv4.nat

[Install]
WantedBy=multi-user.target
EOL
    
    # Enable and start services
    log "Enabling services..."
    systemctl daemon-reload
    systemctl unmask hostapd
    systemctl enable hostapd
    systemctl enable dnsmasq
    systemctl enable wpa_supplicant@${interface}
    systemctl enable iptables-restore
    
    # Create network reconnection script
    log "Creating network reconnection script..."
    cat > /usr/local/bin/ensure-wifi-connection.sh << 'EOL'
#!/bin/bash
# Check WiFi connection and restart if needed

INTERFACE=wlan0
MIN_QUALITY=30
CONNECTION_CHECK_URL="http://google.com"

# Function to get current signal quality
get_signal_quality() {
    # Get signal quality percentage from iwconfig
    local quality=$(iwconfig $INTERFACE | grep -oP 'Quality=\K[0-9]+(?=/[0-9]+)')
    local scale=$(iwconfig $INTERFACE | grep -oP 'Quality=[0-9]+/\K[0-9]+')
    if [ -n "$quality" ] && [ -n "$scale" ]; then
        echo $((quality * 100 / scale))
    else
        echo 0
    fi
}

# Function to check internet connection
check_internet() {
    # Try to connect to google.com
    wget -q --spider $CONNECTION_CHECK_URL
    return $?
}

# Check signal quality
QUALITY=$(get_signal_quality)
echo "Current WiFi signal quality: $QUALITY%"

# Check if connected to the internet
check_internet
INTERNET_STATUS=$?

# Restart WiFi connection if quality is too low or no internet
if [ $QUALITY -lt $MIN_QUALITY ] || [ $INTERNET_STATUS -ne 0 ]; then
    echo "WiFi connection is poor or internet is unavailable. Restarting connection..."
    systemctl restart wpa_supplicant@$INTERFACE
    sleep 10
    systemctl restart networking
    echo "WiFi connection restarted"
fi
EOL
    chmod +x /usr/local/bin/ensure-wifi-connection.sh
    
    # Create cron job for reconnection script
    log "Setting up cron job for connection monitoring..."
    (crontab -l 2>/dev/null; echo "*/5 * * * * /usr/local/bin/ensure-wifi-connection.sh > /dev/null 2>&1") | crontab -
    
    log "AP+STA mode setup complete. Reboot is recommended."
}

# Main function
main() {
    if [ $# -lt 4 ]; then
        echo "Usage: $0 <sta_ssid> <sta_password> <ap_ssid> <ap_password> [interface]"
        echo "Example: $0 'MyHomeWiFi' 'myhomepassword' 'SysoHubAP' 'sysohubpassword' 'wlan0'"
        exit 1
    fi
    
    install_required_packages
    setup_ap_sta_mode "$1" "$2" "$3" "$4" "${5:-wlan0}"
    
    echo "Setup complete. Please reboot your Raspberry Pi."
    read -p "Reboot now? [Y/n]: " reboot_response
    if [ -z "$reboot_response" ] || [ "${reboot_response,,}" = "y" ]; then
        reboot
    fi
}

# Execute main function
main "$@"