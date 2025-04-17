import os
import yaml
import paho.mqtt.client as mqtt
import json
from flask import Flask, render_template
import psutil
import requests
from collections import defaultdict
from threading import Lock
from urllib.parse import urlparse

app = Flask(__name__, template_folder="../static")

# Configuration
CONFIG_FILE = os.path.join(os.path.expanduser("~"), "syhub/config/config.yml")
with open(CONFIG_FILE, 'r') as f:
    config = yaml.safe_load(f)

PROJECT_NAME = config['project']['name']
MQTT_URI = config['project']['mqtt']['uri']
MQTT_PORT = config['project']['mqtt']['port']
MQTT_USERNAME = config['project']['mqtt']['username']
MQTT_PASSWORD = config['project']['mqtt']['password']
MQTT_TOPIC = config['project']['mqtt'].get('topic', 'v1/devices/me/telemetry')  # Fallback if topic is missing
VM_PORT = config['project']['victoria_metrics']['port']
DASHBOARD_PORT = config['project']['dashboard']['port']
MAX_POINTS = 10

# Parse MQTT broker from URI
parsed_uri = urlparse(MQTT_URI)
MQTT_BROKER = parsed_uri.hostname or 'localhost'

# Validate MQTT topic
if not MQTT_TOPIC:
    print("Warning: MQTT topic is empty, using default 'v1/devices/me/telemetry'")
    MQTT_TOPIC = 'v1/devices/me/telemetry'

# In-memory storage for telemetry data
telemetry_data = defaultdict(list)
data_lock = Lock()

# MQTT Callbacks
def on_connect(client, userdata, flags, rc):
    if rc == 0:
        client.subscribe(MQTT_TOPIC)
        print(f"Subscribed to {MQTT_TOPIC}")
    else:
        print(f"MQTT connection failed with code {rc}")

def on_message(client, userdata, msg):
    try:
        payload = json.loads(msg.payload.decode())
        with data_lock:
            for key, value in payload.items():
                telemetry_data[key].append(value)
                if len(telemetry_data[key]) > MAX_POINTS:
                    telemetry_data[key].pop(0)
    except Exception as e:
        print(f"Error processing MQTT message: {e}")

# MQTT Client Setup
mqtt_client = mqtt.Client()
mqtt_client.username_pw_set(MQTT_USERNAME, MQTT_PASSWORD)
mqtt_client.on_connect = on_connect
mqtt_client.on_message = on_message
mqtt_client.connect(MQTT_BROKER, MQTT_PORT)
mqtt_client.loop_start()

# System Stats
def get_system_stats():
    return {
        'cpu': psutil.cpu_percent(),
        'memory': psutil.virtual_memory().percent
    }

# Service Status
def get_service_status():
    services = ['hostapd', 'dnsmasq', 'avahi-daemon', 'mosquitto', 'victoriametrics', 'nodered', 'flask-dashboard']
    status = {}
    for service in services:
        try:
            result = os.popen(f"systemctl is-active {service}").read().strip()
            status[service] = result
        except:
            status[service] = 'unknown'
    return status

# Routes
@app.route('/')
def index():
    with data_lock:
        telemetry_copy = {k: v[:] for k, v in telemetry_data.items()}
    return render_template('index.html',
                          project_name=PROJECT_NAME,
                          telemetry=telemetry_copy,
                          system_stats=get_system_stats(),
                          service_status=get_service_status())

if __name__ == '__main__':
    # Development mode
    app.run(host='0.0.0.0', port=DASHBOARD_PORT, debug=True)