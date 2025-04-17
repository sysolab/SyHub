beeHive IoT Monitoring System
An IoT solution for monitoring plant-related telemetry data (temperature, pH, ORP, TDS, EC, distance) on a Raspberry Pi 3B. Features a WiFi access point + station (AP+STA), MQTT broker (Mosquitto), time-series storage (VictoriaMetrics), minimal data processing (Node-RED), and a Flask-based dashboard.
Project Structure
~/syhub/
├── config/
│   └── config.yml              # Configuration file
├── scripts/
│   └── syhub.sh               # Setup script
├── static/
│   └── index.html             # Flask dashboard HTML
├── templates/
│   ├── dhcpcd.conf.j2         # WiFi AP network configuration
│   ├── hostapd.conf.j2        # WiFi AP settings
│   ├── dnsmasq.conf.j2        # DNS and DHCP settings
│   ├── mosquitto.conf.j2      # Mosquitto configuration
│   ├── victoria_metrics.yml.j2 # VictoriaMetrics configuration
│   └── flask_app.py           # Flask application source
├── flask_app.py               # Deployed Flask application
└── README.md                  # This file

Prerequisites

Raspberry Pi 3B with Raspberry Pi OS 64-bit (Bookworm, Lite recommended).
MicroSD card (8GB+).
Temporary internet access (Ethernet or WiFi) for setup.

Setup Instructions

Prepare the Project Directory:
mkdir -p ~/syhub/{config,scripts,static,templates}


Copy Files: Place all provided files in their respective locations under ~/syhub/. The setup script should be syhub.sh. If you copy syhub.sh to syhub_setup.sh, ensure the contents match exactly (verify with diff). For user plantomioX1, files should be in /home/plantomioX1/syhub/.

Verify config.yml: Ensure config.yml is in ~/syhub/config/config.yml with all required fields. Use 2-space indentation and quote values with special characters (e.g., passwords starting with !):

wifi_ssid and wifi_password: For the WiFi access point (AP mode).
sta_wifi_ssid and sta_wifi_password: For connecting to your router (STA mode).
Other settings: MQTT credentials, ports, etc.

Example config.yml:
project:
  name: plantomio
  wifi_ssid: plantomio_ap
  wifi_password: plantomio123
  sta_wifi_ssid: YourRouterSSID
  sta_wifi_password: "YourRouterPassword"
  mqtt:
    username: plantomioX1
    password: plantomioX1Pass
    port: 1883
    topic: v1/devices/me/telemetry
  victoria_metrics:
    port: 8428
  node_red:
    port: 1880
  dashboard:
    port: 5000
  node_red_username: admin
  node_red_password_hash: "$2b$08$W99V1mAwhUg5M9.hX6kjY.qtLHyvk1YbiXIMQ8T.xafDsGHNEa1Na"

Validate syntax:
yq e '.' ~/syhub/config/config.yml


Generate Node-RED Password Hash:
node-red admin hash-pw YOUR_PASSWORD

Update node_red_password_hash in config.yml with the output.

Set Permissions:
chmod +x ~/syhub/scripts/syhub.sh

If using syhub_setup.sh, ensure it’s identical to syhub.sh:
cp ~/syhub/scripts/syhub.sh ~/syhub/scripts/syhub_setup.sh
chmod +x ~/syhub/scripts/syhub_setup.sh
diff ~/syhub/scripts/syhub.sh ~/syhub/scripts/syhub_setup.sh


Run the Setup Script:
sudo bash ~/syhub/scripts/syhub.sh setup

Or, if using syhub_setup.sh:
sudo bash ~/syhub/scripts/syhub_setup.sh setup

This installs dependencies, sets up WiFi AP+STA using AP_STA_RPI_SAME_WIFI_CHIP, and configures Mosquitto, VictoriaMetrics, Node-RED, and Flask.

Access the System:

Connect to the WiFi AP (plantomio_ap by default).
Verify STA mode: Check router logs or use iwconfig wlan0 to confirm connection to your router.
Access Node-RED at http://plantomio.local:1880/admin (for configuration only).
Access the dashboard at http://plantomio.local:5000.



Usage

Setup: sudo bash ~/syhub/scripts/syhub.sh setup
Update: sudo bash ~/syhub/scripts/syhub.sh update
Purge: sudo bash ~/syhub/scripts/syhub.sh purge
Backup: sudo bash ~/syhub/scripts/syhub.sh backup
Status: sudo bash ~/syhub/scripts/syhub.sh status

Robustness

Error Handling: The setup script checks for dependency installation failures, validates STA WiFi settings, and verifies service startups.
Service Reliability: All services (hostapd, dnsmasq, avahi-daemon, mosquitto, victoriametrics, nodered, flask-dashboard) are configured to restart automatically (Restart=always).
Compatibility: Tested for Raspberry Pi 3B with Raspberry Pi OS 64-bit Bookworm, works on fresh or existing SD cards.
WiFi AP+STA: Uses AP_STA_RPI_SAME_WIFI_CHIP to ensure stable AP and STA modes on the single WiFi chip.

Resource Optimization

Node-RED: Minimal flow (MQTT input to HTTP request), memory limited to 256 MB (--max-old-space-size=256).
VictoriaMetrics: Lightweight with efficient storage compression in /var/lib/victoria-metrics.
Flask Dashboard: Limits in-memory data to 10 points per metric, uses gunicorn with 4 workers for CPU efficiency.
Mosquitto: Configured for minimal overhead with authentication enabled.
WiFi: AP+STA setup optimized for Raspberry Pi 3B’s WiFi chip to avoid resource conflicts.

Troubleshooting

YQ Parsing Errors:

If you see errors like Error: One or more required fields are missing or invalid, check yq parsing:yq e '.' ~/syhub/config/config.yml

If it fails, inspect /tmp/config.yml.errors:cat /tmp/config.yml.errors


Ensure passwords with special characters (e.g., starting with !) are quoted:sta_wifi_password: "!YourPassword"


Verify yq version:yq --version

Ensure it’s version 4.x (e.g., yq (https://github.com/mikefarah/yq/) version v4.35.2).
Reinstall yq if needed:sudo wget https://github.com/mikefarah/yq/releases/download/v4.35.2/yq_linux_arm64 -O /usr/local/bin/yq
sudo chmod +x /usr/local/bin/yq




Config File Issues:

Ensure config.yml exists in ~/syhub/config/config.yml (e.g., /home/plantomioX1/syhub/config/config.yml).
Verify:ls -l ~/syhub/config/config.yml
cat ~/syhub/config/config.yml


If missing or invalid, copy the provided config.yml and update sta_wifi_ssid, sta_wifi_password, etc.


WiFi AP: Check journalctl -u hostapd and /tmp/AP_STA_RPI_SAME_WIFI_CHIP/install.log. Ensure devices connect to the AP (plantomio_ap by default).

WiFi STA: Verify connection to your router with iwconfig wlan0 or check router logs. Ensure sta_wifi_ssid and sta_wifi_password are correct in config.yml.

Mosquitto Failure: If Mosquitto fails to start, check logs:
systemctl status mosquitto.service
journalctl -xeu mosquitto.service

Verify /etc/mosquitto/mosquitto.conf syntax and ensure /etc/mosquitto/passwd exists with correct permissions (chmod 600).

DNSmasq Not Found: If dnsmasq.service is missing, reinstall:
sudo apt install --reinstall dnsmasq

Check service status: systemctl status dnsmasq.

Node-RED Flow Errors: Ensure /home/pi/.node-red/flows.json is correctly formatted. Restart Node-RED:
sudo systemctl restart nodered


VictoriaMetrics: Test data ingestion: curl -X POST 'http://localhost:8428/write' -d 'telemetry,metric=temperature value=25'.

Dashboard: Ensure Flask binds to 0.0.0.0:5000. Check logs: journalctl -u flask-dashboard.


Future Enhancements

Add Chart.js for data visualization in the Flask dashboard.
Implement alerting in Node-RED for threshold breaches.
Schedule backups with cron: 0 0 * * * bash $HOME/syhub/scripts/syhub.sh backup.

References

AP_STA_RPI_SAME_WIFI_CHIP
VictoriaMetrics Quick Start
Mosquitto Installation
Node-RED MQTT Tutorial
Flask on Raspberry Pi
Minimal Node-RED Setup

