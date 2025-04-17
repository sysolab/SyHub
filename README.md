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


Copy Files: Place all provided files in their respective locations under ~/syhub/. Ensure the setup script is named syhub.sh (not syhub_setup.sh).

Update config.yml: Modify ~/syhub/config/config.yml with your desired settings:

wifi_ssid and wifi_password: For the WiFi access point (AP mode).
sta_wifi_ssid and sta_wifi_password: For connecting to your router (STA mode).
Other settings: MQTT credentials, ports, etc.


Generate Node-RED Password Hash:
node-red admin hash-pw YOUR_PASSWORD

Update node_red_password_hash in config.yml with the output.

Run the Setup Script:
sudo bash ~/syhub/scripts/syhub.sh setup

This installs dependencies, sets up WiFi AP+STA using AP_STA_RPI_SAME_WIFI_CHIP, and configures Mosquitto, VictoriaMetrics, Node-RED, and Flask. If errors occur, check service logs (see Troubleshooting).

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
Schedule backups with cron: 0 0 * * * $HOME/syhub/scripts/syhub.sh backup.

References

AP_STA_RPI_SAME_WIFI_CHIP
VictoriaMetrics Quick Start
Mosquitto Installation
Node-RED MQTT Tutorial
Flask on Raspberry Pi
Minimal Node-RED Setup

