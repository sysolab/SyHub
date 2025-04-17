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
├── flask_app_deployed.py      # Deployed Flask application
├── venv/                      # Python virtual environment
├── backups/                   # Backup directory
└── README.md                  # This file

Prerequisites

Raspberry Pi 3B with Raspberry Pi OS 64-bit (Bookworm, Lite recommended).
MicroSD card (8GB+).
Temporary internet access (Ethernet or WiFi) for setup.

Setup Instructions

Prepare the Project Directory:
mkdir -p ~/syhub/{config,scripts,static,templates,backups}


Copy Files: Place all provided files in their respective locations under ~/syhub/. The setup script is syhub.sh. For user plantomioX1, files should be in /home/plantomioX1/syhub/.

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


Clean Up Previous Setup (if needed):
sudo bash ~/syhub/scripts/syhub.sh purge


Run the Setup Script:
sudo bash ~/syhub/scripts/syhub.sh setup

This installs dependencies, sets up WiFi AP+STA using AP_STA_RPI_SAME_WIFI_CHIP, and configures Mosquitto, VictoriaMetrics, Node-RED, and Flask. Logs are written to /tmp/syhub_setup.log.

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

Error Handling: Checks for dependency installation failures, validates STA WiFi settings, and verifies service startups. Retries network operations (e.g., wget, git clone).
Service Reliability: All services (hostapd, dnsmasq, avahi-daemon, mosquitto, victoriametrics, nodered, flask-dashboard) are configured to restart automatically (Restart=always).
Compatibility: Tested for Raspberry Pi 3B with Raspberry Pi OS 64-bit Bookworm.
WiFi AP+STA: Uses AP_STA_RPI_SAME_WIFI_CHIP for stable AP and STA modes.
Logging: Detailed logs in /tmp/syhub_setup.log for debugging.

Resource Optimization

Node-RED: Minimal flow, memory limited to 256 MB (--max-old-space-size=256).
VictoriaMetrics: Lightweight with efficient storage in /var/lib/victoria-metrics.
Flask Dashboard: Uses gunicorn with 4 workers, runs in a virtual environment.
Mosquitto: Minimal overhead with authentication enabled.
WiFi: Optimized for Raspberry Pi 3B’s WiFi chip.

Troubleshooting

APT Lock Issues:

If you see Waiting for cache lock: Could not get lock /var/lib/dpkg/lock-frontend:
sudo killall apt apt-get
sudo rm -f /var/lib/dpkg/lock-frontend /var/cache/apt/archives/lock
sudo dpkg --configure -a
sudo apt update


Check /tmp/syhub_setup.log for details.



DNSmasq Configuration Conflict:

If dnsmasq installation fails due to /etc/dnsmasq.conf:
sudo mv /etc/dnsmasq.conf /etc/dnsmasq.conf.bak
sudo dpkg --configure -a
sudo apt install -y dnsmasq


The script backs up existing configs to /etc/dnsmasq.conf.bak-<date>.



VictoriaMetrics Download Failure:

If wget fails, check the URL:
wget https://github.com/VictoriaMetrics/VictoriaMetrics/releases/download/v1.93.0/victoria-metrics-arm-v1.93.0.tar.gz


Ensure internet connectivity: ping github.com.



Python Package Installation:

The script uses a virtual environment (~/syhub/venv). To manually install packages:
source ~/syhub/venv/bin/activate
pip install flask gunicorn paho-mqtt requests psutil
deactivate




YQ Parsing Errors:

Check /tmp/config.yml.errors and /tmp/config.yml.parsed:
cat /tmp/config.yml.errors
cat /tmp/config.yml.parsed


Validate config.yml:
yq e '.' ~/syhub/config/config.yml




WiFi AP: Check journalctl -u hostapd and /tmp/AP_STA_RPI_SAME_WIFI_CHIP/install.log.

WiFi STA: Verify connection:
iwconfig wlan0


Mosquitto: Check logs:
journalctl -xeu mosquitto.service


Node-RED: Access http://plantomio.local:1880/admin and verify /home/pi/.node-red/flows.json.

VictoriaMetrics: Test ingestion:
curl -X POST 'http://localhost:8428/write' -d 'telemetry,metric=temperature value=25'


Dashboard: Check journalctl -u flask-dashboard.


Future Enhancements

Add Chart.js to the Flask dashboard.
Implement alerting in Node-RED.
Schedule backups: 0 0 * * * bash $HOME/syhub/scripts/syhub.sh backup.

References

AP_STA_RPI_SAME_WIFI_CHIP
VictoriaMetrics Quick Start
Mosquitto Installation
Node-RED MQTT Tutorial
Flask on Raspberry Pi
PEP 668

