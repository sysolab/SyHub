#!/bin/bash

# /home/<YOUR_USER>/syhub/scripts/syhub.sh
# Setup, Update, Purge, Backup, Status script for the syHub Monitoring System

# --- Safety and Configuration ---
set -o errexit  # Exit immediately if a command exits with a non-zero status.
set -o nounset  # Treat unset variables as an error when substituting.
set -o pipefail # Return value of a pipeline is the value of the last command to exit with a non-zero status

# --- Script Information ---
SCRIPT_NAME=$(basename "$0")
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SYHUB_BASE_DIR=$(cd "${SCRIPT_DIR}/.." && pwd) # Assumes script is in scripts/ subdir

# --- User and Paths ---
# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "ERROR: This script must be run as root using sudo."
   exit 1
fi

# Determine the non-root user who invoked sudo
APP_USER="${SUDO_USER:-$(logname 2>/dev/null || echo 'nobody')}"
if [[ "$APP_USER" == "root" || "$APP_USER" == "nobody" ]]; then
    echo "ERROR: Could not determine the non-root user who invoked sudo."
    echo "Please run as 'sudo -u <your_user> bash $0' or ensure SUDO_USER is set."
    exit 1
fi

# Get the user's primary group
APP_GROUP=$(id -gn "$APP_USER")
# Get the user's home directory
APP_HOME=$(getent passwd "$APP_USER" | cut -d: -f6)
if [[ ! -d "$APP_HOME" ]]; then
    echo "ERROR: Home directory for user '$APP_USER' not found at '$APP_HOME'."
    exit 1
fi

# Verify SYHUB_BASE_DIR matches expected structure based on APP_HOME
EXPECTED_BASE_DIR="$APP_HOME/syhub"
if [[ "$SYHUB_BASE_DIR" != "$EXPECTED_BASE_DIR" ]]; then
    echo "ERROR: Script is not located in the expected directory: $EXPECTED_BASE_DIR/scripts/"
    echo "       Detected base directory: $SYHUB_BASE_DIR"
    exit 1
fi

# Define core paths relative to the detected base directory
CONFIG_FILE="$SYHUB_BASE_DIR/config/config.yml"
TEMPLATE_DIR="$SYHUB_BASE_DIR/templates"
STATIC_DIR="$SYHUB_BASE_DIR/static"
VENV_DIR="$SYHUB_BASE_DIR/venv"
BACKUP_BASE_DIR="$SYHUB_BASE_DIR/backups" # Base, specific dir created later
DEPLOYED_FLASK_APP="$SYHUB_BASE_DIR/flask_app_deployed.py"
NODE_RED_DATA_DIR="$APP_HOME/.node-red" # Default Node-RED data location

# --- Load Configuration ---
# Function to safely read values from YAML config using yq
# Requires yq to be installed (handled in setup_dependencies)
config_get() {
    local key="$1"
    local default_value="${2:-}" # Optional default value
    local value

    # Attempt to read the value using yq.
    # -e: evaluate expression
    # -r: output raw scalar value (removes quotes from strings etc.)
    # Redirect stderr to /dev/null to suppress yq errors if key not found.
    # Use '|| true' to prevent script exit via 'set -o errexit' if yq fails (e.g., key not found).
    value=$(yq e -r ".$key" "$CONFIG_FILE" 2>/dev/null || true)

    # Check if yq returned an empty string or the literal string "null"
    if [[ -z "$value" || "$value" == "null" ]]; then
        if [[ -n "$default_value" ]]; then
            # A default was provided, use it
            echo "$default_value"
            # Optional: Log that a default is being used (can be noisy)
            # log_message "DEBUG" "Config key '$key' not found or null in '$CONFIG_FILE', using provided default."
        else
            # No default value was provided, and the key is missing or null.
            # This indicates a required configuration is missing.
            log_message "ERROR" "Mandatory configuration key '$key' is missing, null, or empty in '$CONFIG_FILE'."
            exit 1
        fi
    else
        # Value found and is not null/empty
        echo "$value"
    fi
}

# --- Logging ---
LOG_FILE="/tmp/syhub_placeholder_log.log" # Placeholder, updated after reading config
setup_logging() {
    # Read log file path from config AFTER yq is installed
    LOG_FILE=$(config_get 'log_file' '/tmp/syhub_setup_default.log')
    # Ensure log directory exists (e.g., /tmp) - usually does
    mkdir -p "$(dirname "$LOG_FILE")"
    # Redirect stdout and stderr to the log file AND the console
    # exec &> >(tee -a "$LOG_FILE") # tee can sometimes buffer unexpectedly in scripts
    exec > >(tee -a "$LOG_FILE")
    exec 2> >(tee -a "$LOG_FILE" >&2)
    log_message "INFO" "--- Starting $SCRIPT_NAME $1 ---"
    log_message "INFO" "Timestamp: $(date)"
    log_message "INFO" "Running as user: $(whoami) (Invoked by: $APP_USER)"
    log_message "INFO" "SyHub Base Directory: $SYHUB_BASE_DIR"
    log_message "INFO" "Configuration File: $CONFIG_FILE"
    log_message "INFO" "Log File: $LOG_FILE"
}

log_message() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" # Will be redirected by exec
}

# --- Helper Functions ---

# Check internet connection
check_internet() {
    log_message "INFO" "Checking internet connectivity..."
    if ! ping -c 1 github.com &> /dev/null; then
        log_message "WARNING" "Cannot ping github.com. Internet might be down or DNS issues."
        if ! curl -Is https://github.com | head -n 1 | grep -q "200 OK"; then
             log_message "ERROR" "Failed to reach github.com via HTTPs. Internet connection required for setup."
             exit 1
        fi
         log_message "INFO" "Can reach github.com via HTTPs, proceeding."
    else
        log_message "INFO" "Internet connection verified."
    fi
}

# Process a template file using sed for simple substitution
process_template() {
    local template_path="$1"
    local output_path="$2"
    local temp_file

    if [[ ! -f "$template_path" ]]; then
        log_message "ERROR" "Template file not found: $template_path"
        exit 1
    fi

    temp_file=$(mktemp)
    cp "$template_path" "$temp_file"

    log_message "INFO" "Processing template $template_path -> $output_path"

    # Dynamically create sed expressions for all loaded config variables
    local sed_expressions=""
    # Use process substitution and mapfile to read variable names from associative array keys
    mapfile -t config_keys < <(printf "%s\n" "${!CONFIG[@]}")

    for key_upper in "${config_keys[@]}"; do
         # Placeholder format: __KEY_UPPER__
         placeholder="__${key_upper}__"
         value="${CONFIG[$key_upper]}"
         # Escape sed special characters: / & \
         escaped_value=$(sed -e 's/[\/&]/\\&/g' <<< "$value")
         sed_expressions+=" -e s|${placeholder}|${escaped_value}|g" # Using | as delimiter
    done

    # Execute sed with all expressions
    # shellcheck disable=SC2086 # We need word splitting for sed_expressions
    sed $sed_expressions "$temp_file" > "$output_path"

    rm "$temp_file"
    log_message "INFO" "Generated $output_path"
}

# Install packages if they are not already installed
install_packages() {
    local packages_to_install=()
    for pkg in "$@"; do
        if ! dpkg -s "$pkg" &> /dev/null; then
            packages_to_install+=("$pkg")
        else
             log_message "INFO" "Package '$pkg' is already installed."
        fi
    done

    if [[ ${#packages_to_install[@]} -gt 0 ]]; then
        log_message "INFO" "Updating package lists..."
        apt-get update -y || { log_message "ERROR" "apt-get update failed."; exit 1; }

        log_message "INFO" "Installing missing packages: ${packages_to_install[*]}"
        # Disable interactive prompts during installation
        DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages_to_install[@]}" || {
            log_message "ERROR" "Failed to install packages: ${packages_to_install[*]}. Trying dependencies..."
            # Attempt to fix broken dependencies
             DEBIAN_FRONTEND=noninteractive apt-get --fix-broken install -y || {
                 log_message "ERROR" "apt-get --fix-broken install failed. Cannot proceed."
                 exit 1
             }
             # Retry installation
             DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages_to_install[@]}" || {
                 log_message "ERROR" "Failed to install packages even after fixing dependencies: ${packages_to_install[*]}. Cannot proceed."
                 exit 1
             }
        }
        log_message "INFO" "Packages installed successfully."
    else
        log_message "INFO" "All required packages are already installed."
    fi
}

# --- Core Setup Functions ---

# --- Core Setup Functions ---

setup_dependencies() {
    log_message "INFO" "Installing core dependencies..."
    # yq: For YAML parsing. Using binary download for consistency. Find latest at https://github.com/mikefarah/yq/releases
    YQ_VERSION="v4.45.1" # Specify desired version
    YQ_BINARY="yq_linux_arm64"
    if ! command -v yq &> /dev/null || [[ "$(yq --version)" != *"$YQ_VERSION"* ]]; then
        log_message "INFO" "Installing yq ${YQ_VERSION}..."
        wget "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/${YQ_BINARY}.tar.gz" -O /tmp/yq.tar.gz || {
             log_message "ERROR" "Failed to download yq archive."
             exit 1
        }
        # Extract directly into /tmp. We only care about the binary itself.
        tar xzf /tmp/yq.tar.gz -C /tmp || {
             log_message "ERROR" "Failed to extract yq archive."
             # Clean up partial download before exiting
             rm -f /tmp/yq.tar.gz
             exit 1
        }
        # Check if the expected binary exists after extraction
        if [[ ! -f "/tmp/${YQ_BINARY}" ]]; then
            log_message "ERROR" "Expected yq binary '${YQ_BINARY}' not found in /tmp after extraction."
             # Clean up archive and any other extracted files we know about
            rm -f /tmp/yq.tar.gz /tmp/LICENSE /tmp/README.md
            exit 1
        fi

        # Move the binary to the destination
        mv "/tmp/${YQ_BINARY}" /usr/local/bin/yq || {
             log_message "ERROR" "Failed to move yq binary to /usr/local/bin/yq."
             # Clean up archive and any other extracted files
             rm -f /tmp/yq.tar.gz /tmp/LICENSE /tmp/README.md
             exit 1
        }
        chmod +x /usr/local/bin/yq

        # --- Robust Cleanup ---
        # Use rm -f to forcefully remove files and ignore errors if they don't exist.
        log_message "INFO" "Cleaning up temporary yq installation files..."
        rm -f /tmp/yq.tar.gz /tmp/LICENSE /tmp/README.md
        # --- End Robust Cleanup ---

        log_message "INFO" "yq installed: $(yq --version)"
    else
         log_message "INFO" "yq is already installed: $(yq --version)"
    fi

    # Essential system packages
    install_packages \
        git \
        wget \
        curl \
        build-essential \
        python3-venv \
        python3-pip \
        avahi-daemon \
        avahi-utils \
        hostapd \
        dnsmasq \
        mosquitto \
        mosquitto-clients \
        rfkill # For unblocking wifi

    # Verify config file exists *before* trying to read it
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_message "ERROR" "Configuration file not found: $CONFIG_FILE"
        exit 1
    fi
    # Now that yq is installed, setup proper logging using config value
    # NOTE: setup_logging was called initially with a placeholder,
    #       re-calling it here might re-initialize logs, which is fine,
    #       or we can just read the log_file value and set the global LOG_FILE var.
    #       Let's just set the variable directly if it hasn't been set properly yet.
    if [[ "$LOG_FILE" == "/tmp/syhub_placeholder_log.log" ]]; then
         LOG_FILE=$(config_get 'log_file' '/tmp/syhub_setup_default.log')
         log_message "INFO" "Log file set to: $LOG_FILE"
         # Re-apply redirection if needed (though initial exec should persist)
         # exec > >(tee -a "$LOG_FILE")
         # exec 2> >(tee -a "$LOG_FILE" >&2)
    fi


    log_message "INFO" "Core dependencies installed."
}

load_all_config() {
    log_message "INFO" "Loading all configuration values from $CONFIG_FILE..."
    declare -gA CONFIG # Declare CONFIG as a global associative array

    # Read all keys at the top level and under known sections
    local keys_to_read=(
        "project.name"
        "hostname"
        "log_file"
        "backup_directory"
        "configure_network"
        "wifi.ap_interface" "wifi.ap_ip" "wifi.ap_subnet_mask" "wifi.ap_dhcp_range_start" "wifi.ap_dhcp_range_end" "wifi.ap_dhcp_lease_time" "wifi.ap_ssid" "wifi.ap_password" "wifi.country_code" # <-- Added country_code
        "wifi.sta_ssid" "wifi.sta_password"
        "mqtt.port" "mqtt.username" "mqtt.client_id_base" "mqtt.password" "mqtt.topic_telemetry"
        "victoria_metrics.version" "victoria_metrics.port" "victoria_metrics.data_directory" "victoria_metrics.retention_period" "victoria_metrics.service_user" "victoria_metrics.service_group"
        "node_red.port" "node_red.memory_limit_mb" "node_red.username" "node_red.password_hash"
        "dashboard.port" "dashboard.workers"
        "nodejs.install_version"
    )

    for key in "${keys_to_read[@]}"; do
        # Convert dot notation to uppercase underscore for shell variable name
        local var_name="${key//./_}" # Replace . with _
        var_name="${var_name//-/_}" # Replace - with _
        var_name="${var_name^^}"   # Convert to uppercase
        # Store in associative array
        CONFIG["$var_name"]=$(config_get "$key")
    done

    # Add derived/dynamic values
    CONFIG["APP_USER"]="$APP_USER"
    CONFIG["APP_GROUP"]="$APP_GROUP"
    CONFIG["BASE_DIR"]="$SYHUB_BASE_DIR"
    CONFIG["VENV_DIR"]="$VENV_DIR"
    CONFIG["CONFIG_FILE_PATH"]="$CONFIG_FILE"
    CONFIG["NODE_RED_DATA_DIR"]="$NODE_RED_DATA_DIR"
    CONFIG["MQTT_URI"]="mqtt://${CONFIG[HOSTNAME]}:${CONFIG[MQTT_PORT]}" # Construct MQTT URI
    CONFIG["PROJECT_NAME_UPPER"]="${CONFIG[PROJECT_NAME]^^}" # Uppercase project name if needed

    log_message "INFO" "Configuration loaded successfully."
    # Optional: Print loaded config for debugging (be careful with secrets)
    # log_message "DEBUG" "Loaded Config: $(declare -p CONFIG)"
}


# Function to set up WiFi AP+STA Mode, Hostname, and mDNS
setup_network() {
    log_message "INFO" "--- Checking Network Setup Configuration ---"

    # Check the configuration flag
    if [[ "${CONFIG[CONFIGURE_NETWORK],,}" != "true" ]]; then
        log_message "INFO" "configure_network is not 'true' in config.yml. Skipping AP+STA network configuration."
        # Still configure hostname and basic Avahi if needed, as they don't strictly depend on AP+STA mode
        # --- Configure system hostname ---
        log_message "INFO" "Setting hostname to ${CONFIG[HOSTNAME]}"
        local current_hostname
        current_hostname=$(hostnamectl status --static)
        if [[ "$current_hostname" != "${CONFIG[HOSTNAME]}" ]]; then
            hostnamectl set-hostname "${CONFIG[HOSTNAME]}"
            log_message "INFO" "Hostname updated."
            if grep -q "127.0.1.1" /etc/hosts; then sed -i "s/^\(127\.0\.1\.1\s*\).*/\1${CONFIG[HOSTNAME]}/" /etc/hosts; else echo "127.0.1.1    ${CONFIG[HOSTNAME]}" >> /etc/hosts; fi
            log_message "INFO" "/etc/hosts updated for ${CONFIG[HOSTNAME]}."
            # Restart Avahi daemon after hostname change
            log_message "INFO" "Restarting avahi-daemon due to hostname change..."
            if systemctl is-active --quiet avahi-daemon; then systemctl restart avahi-daemon; else log_message "INFO" "avahi-daemon not active, skipping restart."; fi
        else
            log_message "INFO" "Hostname already set to ${CONFIG[HOSTNAME]}."
        fi

        # --- Configure Basic Avahi mDNS Service Definition ---
        # Advertise basic device info even if full network setup is skipped
        log_message "INFO" "Configuring minimal Avahi (mDNS/Bonjour Service Definitions)..."
        if [[ -f "$TEMPLATE_DIR/syhub-avahi.service.j2" ]]; then
             process_template "$TEMPLATE_DIR/syhub-avahi.service.j2" "/etc/avahi/services/syhub.service"
             chmod 644 "/etc/avahi/services/syhub.service"
             systemctl enable avahi-daemon &> /dev/null # Ensure enabled
             systemctl restart avahi-daemon # Restart to pick up changes
             log_message "INFO" "Avahi service definition updated/created."
        else
             log_message "WARNING" "Avahi template ($TEMPLATE_DIR/syhub-avahi.service.j2) not found. Cannot configure mDNS service discovery."
        fi
        log_message "INFO" "--- Network Setup Skipped (AP+STA Mode) ---"
        return 0 # Exit the function successfully
    fi

    # --- Proceed with Full Network Setup ---
    log_message "INFO" "--- Starting Full Network Setup (configure_network=true) ---"

    # --- Configure system hostname (if not already done above) ---
    log_message "INFO" "Setting/Verifying hostname: ${CONFIG[HOSTNAME]}"
    local current_hostname
    current_hostname=$(hostnamectl status --static)
    if [[ "$current_hostname" != "${CONFIG[HOSTNAME]}" ]]; then
        hostnamectl set-hostname "${CONFIG[HOSTNAME]}"
        log_message "INFO" "Hostname updated."
        if grep -q "127.0.1.1" /etc/hosts; then sed -i "s/^\(127\.0\.1\.1\s*\).*/\1${CONFIG[HOSTNAME]}/" /etc/hosts; else echo "127.0.1.1    ${CONFIG[HOSTNAME]}" >> /etc/hosts; fi
        log_message "INFO" "/etc/hosts updated for ${CONFIG[HOSTNAME]}."
        # Restart Avahi daemon after hostname change
        log_message "INFO" "Restarting avahi-daemon due to hostname change..."
        if systemctl is-active --quiet avahi-daemon; then systemctl restart avahi-daemon; else log_message "INFO" "avahi-daemon not active, skipping restart."; fi
    else
        log_message "INFO" "Hostname already set to ${CONFIG[HOSTNAME]}."
    fi

    # --- Configure Avahi mDNS Service Definition ---
    log_message "INFO" "Configuring Avahi (mDNS/Bonjour Service Definitions)..."
    if [[ ! -f "$TEMPLATE_DIR/syhub-avahi.service.j2" ]]; then
        log_message "ERROR" "Avahi template not found at $TEMPLATE_DIR/syhub-avahi.service.j2"
        exit 1
    fi
    process_template "$TEMPLATE_DIR/syhub-avahi.service.j2" "/etc/avahi/services/syhub.service"
    chmod 644 "/etc/avahi/services/syhub.service"
    systemctl enable avahi-daemon &> /dev/null # Ensure enabled
    systemctl restart avahi-daemon # Restart to pick up changes
    log_message "INFO" "Avahi service definition updated/created."

    # --- Prepare for AP+STA Script Execution ---
    local ap_sta_log_dir="/var/log/ap_sta_wifi"
    log_message "INFO" "Ensuring AP/STA log directory exists: $ap_sta_log_dir"
    mkdir -p "$ap_sta_log_dir"
    chown root:adm "$ap_sta_log_dir" # Group adm can often read logs
    chmod 750 "$ap_sta_log_dir" # Root rwx, group rx

    local cron_log_file_ap0_mgnt="$ap_sta_log_dir/ap0_mgnt.log"
    local cron_log_file_on_boot="$ap_sta_log_dir/on_boot.log"

    touch "$cron_log_file_ap0_mgnt" "$cron_log_file_on_boot"
    chown root:adm "$cron_log_file_ap0_mgnt" "$cron_log_file_on_boot"
    chmod 640 "$cron_log_file_ap0_mgnt" "$cron_log_file_on_boot" # Root rw, group r

    # --- Set Environment Variables for Scripts ---
    log_message "INFO" "Exporting configuration as environment variables for AP/STA scripts..."
    # Use default values here primarily as fallback, syhub.sh load_all_config should enforce mandatory ones
    export SYHUB_AP_SSID="${CONFIG[WIFI_AP_SSID]}"
    export SYHUB_AP_PASSWORD="${CONFIG[WIFI_AP_PASSWORD]:-}" # Allow empty
    export SYHUB_CLIENT_SSID="${CONFIG[WIFI_STA_SSID]}"
    export SYHUB_CLIENT_PASSWORD="${CONFIG[WIFI_STA_PASSWORD]:-}" # Allow empty
    export SYHUB_COUNTRY_CODE="${CONFIG[WIFI_COUNTRY_CODE]}"
    export SYHUB_AP_IP="${CONFIG[WIFI_AP_IP]}"
    # Optional - Add WIFI_MODE to config.yml if needed
    # export SYHUB_WIFI_MODE="${CONFIG[WIFI_MODE]:-'g'}"
    # Flags - Could be made configurable too
    export SYHUB_AP_ONLY="false"
    export SYHUB_STA_ONLY="false"
    export SYHUB_NO_INTERNET="false" # Set to true in config? Or fixed based on project needs?
    export SYHUB_HOSTNAME="${CONFIG[HOSTNAME]}"
    export SYHUB_BASE_DIR="$SYHUB_BASE_DIR"

    # Log file paths for the cron script
    export SYHUB_CRON_LOG_FILE_AP0_MGNT="$cron_log_file_ap0_mgnt"
    export SYHUB_CRON_LOG_FILE_ON_BOOT="$cron_log_file_on_boot"

    # --- Execute Local AP+STA Configuration Script ---
    local ap_sta_config_script="$SCRIPT_DIR/ap_sta_config.sh"
    log_message "INFO" "Executing local script: $ap_sta_config_script"
    if [[ ! -f "$ap_sta_config_script" ]]; then
        log_message "ERROR" "AP+STA config script not found at $ap_sta_config_script"
        # Unset env vars before exiting
        unset SYHUB_AP_SSID SYHUB_AP_PASSWORD SYHUB_CLIENT_SSID SYHUB_CLIENT_PASSWORD SYHUB_COUNTRY_CODE SYHUB_AP_IP SYHUB_WIFI_MODE SYHUB_AP_ONLY SYHUB_STA_ONLY SYHUB_NO_INTERNET SYHUB_HOSTNAME SYHUB_BASE_DIR SYHUB_CRON_LOG_FILE_AP0_MGNT SYHUB_CRON_LOG_FILE_ON_BOOT
        exit 1
    fi
    if ! bash "$ap_sta_config_script"; then
        log_message "ERROR" "Local script ap_sta_config.sh failed. Check its output/logs."
        unset SYHUB_AP_SSID SYHUB_AP_PASSWORD SYHUB_CLIENT_SSID SYHUB_CLIENT_PASSWORD SYHUB_COUNTRY_CODE SYHUB_AP_IP SYHUB_WIFI_MODE SYHUB_AP_ONLY SYHUB_STA_ONLY SYHUB_NO_INTERNET SYHUB_HOSTNAME SYHUB_BASE_DIR SYHUB_CRON_LOG_FILE_AP0_MGNT SYHUB_CRON_LOG_FILE_ON_BOOT
        exit 1
    fi
    log_message "INFO" "Local script ap_sta_config.sh finished execution."

    # Unset non-cron related environment variables after use
    unset SYHUB_AP_SSID SYHUB_AP_PASSWORD SYHUB_CLIENT_SSID SYHUB_CLIENT_PASSWORD SYHUB_COUNTRY_CODE SYHUB_AP_IP SYHUB_WIFI_MODE SYHUB_AP_ONLY SYHUB_STA_ONLY SYHUB_NO_INTERNET SYHUB_HOSTNAME SYHUB_BASE_DIR

    # --- Execute Local AP+STA Cron Script ---
    # Ensure root's crontab is initialized if it doesn't exist yet
    if crontab -l &> /dev/null && [[ 1 -eq $(crontab -l | grep -cF "no crontab for root") ]]; then
         log_message "INFO" "Initializing root's crontab..."
         (crontab -l 2>/dev/null; echo "# Initialized by syhub.sh $(date)") | crontab - || {
              log_message "WARNING" "Failed to initialize root's crontab. Cron jobs might not be set up."
         }
    else
        log_message "INFO" "Root's crontab already exists or initialized."
    fi

    local ap_sta_cron_script="$SCRIPT_DIR/ap_sta_cron.sh"
    log_message "INFO" "Executing local script: $ap_sta_cron_script"
    if [[ ! -f "$ap_sta_cron_script" ]]; then
        log_message "ERROR" "AP+STA cron script not found at $ap_sta_cron_script"
        unset SYHUB_CRON_LOG_FILE_AP0_MGNT SYHUB_CRON_LOG_FILE_ON_BOOT
        exit 1
    fi
    if ! bash "$ap_sta_cron_script"; then
        log_message "ERROR" "Local script ap_sta_cron.sh failed. Check its output/logs."
        unset SYHUB_CRON_LOG_FILE_AP0_MGNT SYHUB_CRON_LOG_FILE_ON_BOOT
        exit 1
    fi
    log_message "INFO" "Local script ap_sta_cron.sh finished execution."

    # Unset environment variables after use
    unset SYHUB_CRON_LOG_FILE_AP0_MGNT SYHUB_CRON_LOG_FILE_ON_BOOT

    # --- Verification Step ---
    local expected_ap_ip="${CONFIG[WIFI_AP_IP]}"
    local ap_interface="${CONFIG[WIFI_AP_INTERFACE]}" # Use interface name from config

    log_message "INFO" "Verifying network interface configuration after script execution..."
    sleep 5 # Allow network services time to settle
    local verify_attempts=6
    local verify_success=false
    for ((i=1; i<=verify_attempts; i++)); do
        log_message "INFO" "Verification attempt $i/$verify_attempts for IP $expected_ap_ip on $ap_interface..."
        # Check if interface exists and has the IP assigned
        if ip addr show "$ap_interface" &> /dev/null && ip addr show "$ap_interface" | grep -q "inet $expected_ap_ip/"; then
            log_message "INFO" "Successfully verified IP $expected_ap_ip on interface $ap_interface."
            verify_success=true
            break
        else
            log_message "WARNING" "Attempt $i: Interface $ap_interface or IP $expected_ap_ip not found/assigned yet."
            if [[ $i -lt $verify_attempts ]]; then
                log_message "INFO" "Retrying verification in 10 seconds..."
                sleep 10
            fi
        fi
    done

    if ! $verify_success; then
        log_message "ERROR" "Failed to verify expected AP IP $expected_ap_ip on $ap_interface after $verify_attempts attempts."
        log_message "ERROR" "Check logs in $ap_sta_log_dir, config files in /etc/, and journalctl for hostapd, dnsmasq, dhcpcd, networking."
         # Check if the script used its internal default IP (192.168.50.1)
        if ip addr show "$ap_interface" &> /dev/null && ip addr show "$ap_interface" | grep -q "inet 192.168.50.1/"; then
             log_message "WARNING" "Detected fallback IP 192.168.50.1 instead of expected $expected_ap_ip on $ap_interface."
             log_message "WARNING" "Ensure SYHUB_AP_IP environment variable was correctly passed to ap_sta_config.sh or update config.yml."
        fi
        exit 1 # Exit if verification fails
    fi
    # --- End Verification Step ---

    # --- Network Service Status Check ---
    log_message "INFO" "Verifying core network service statuses..."
    local core_network_services=( hostapd dnsmasq dhcpcd wpa_supplicant) # Added wpa_supplicant
    for service in "${core_network_services[@]}"; do
         if systemctl is-active --quiet "$service"; then
             log_message "INFO" "Service '$service' is active."
         else
             # wpa_supplicant might not be active if STA fails connection, treat as warning
             if [[ "$service" == "wpa_supplicant" ]]; then
                 log_message "WARNING" "Service '$service' is NOT active. STA connection likely failed. Check 'iwconfig wlan0' and logs: journalctl -u $service"
             else
                  log_message "ERROR" "Service '$service' is NOT active. Check logs: journalctl -u $service"
                  # Consider exiting if hostapd or dnsmasq fail
                  # exit 1
             fi
         fi
    done

    log_message "INFO" "--- Full Network Setup Finished ---"
    log_message "INFO" "AP SSID: ${CONFIG[WIFI_AP_SSID]} should be visible."
    log_message "INFO" "STA Connection: Should attempt connection to ${CONFIG[WIFI_STA_SSID]}. Check router logs or 'iwconfig wlan0'."
    log_message "INFO" "Hostname: ${CONFIG[HOSTNAME]}"
    log_message "INFO" "AP IP Address appears to be: $(ip addr show "$ap_interface" | grep "inet " | awk '{print $2}' | cut -d/ -f1 || echo "Not Detected")"
    log_message "INFO" "Access dashboard (once set up) at http://${CONFIG[HOSTNAME]}:${CONFIG[DASHBOARD_PORT]}"
    log_message "INFO" "AP/STA script logs are in $ap_sta_log_dir"
}



setup_mqtt() {
    log_message "INFO" "Setting up Mosquitto MQTT Broker..."

    # Configure Mosquitto listener and authentication
    mkdir -p /etc/mosquitto/conf.d/
    process_template "$TEMPLATE_DIR/mosquitto.conf.j2" "/etc/mosquitto/conf.d/syhub.conf"
    chmod 644 /etc/mosquitto/conf.d/syhub.conf

    # Create password file
    log_message "INFO" "Creating MQTT password file for user: ${CONFIG[MQTT_USERNAME]}"
    # Use -c to create, -b for batch mode (password on command line)
    touch /etc/mosquitto/passwd # Create file first
    mosquitto_passwd -b /etc/mosquitto/passwd "${CONFIG[MQTT_USERNAME]}" "${CONFIG[MQTT_PASSWORD]}" || {
        log_message "ERROR" "Failed to add user ${CONFIG[MQTT_USERNAME]} to Mosquitto password file."
        exit 1
    }
    # Set permissions for mosquitto user/group
    chown mosquitto:mosquitto /etc/mosquitto/passwd
    chmod 600 /etc/mosquitto/passwd # Only readable by owner (mosquitto)

    # Ensure persistence directory exists and has correct owner
    local persistence_dir="/var/lib/mosquitto"
    mkdir -p "$persistence_dir"
    chown mosquitto:mosquitto "$persistence_dir"
    chmod 700 "$persistence_dir"

    # Ensure log directory exists and has correct owner
    local log_dir="/var/log/mosquitto"
    mkdir -p "$log_dir"
    chown mosquitto:mosquitto "$log_dir"
    chmod 740 "$log_dir" # Writable by mosquitto, readable by group (e.g., adm)

    log_message "INFO" "Enabling and restarting Mosquitto service..."
    systemctl enable mosquitto.service
    systemctl restart mosquitto.service

    log_message "INFO" "Mosquitto setup complete. Listening on port ${CONFIG[MQTT_PORT]}."
}

setup_victoriametrics() {
    log_message "INFO" "Setting up VictoriaMetrics ${CONFIG[VICTORIA_METRICS_VERSION]}..."
    local vm_version="${CONFIG[VICTORIA_METRICS_VERSION]}"
    local vm_user="${CONFIG[VICTORIA_METRICS_SERVICE_USER]}"
    local vm_group="${CONFIG[VICTORIA_METRICS_SERVICE_GROUP]}"
    local vm_data_dir="${CONFIG[VICTORIA_METRICS_DATA_DIRECTORY]}"
    local vm_binary="/usr/local/bin/victoria-metrics-prod"
    local vm_url="https://github.com/VictoriaMetrics/VictoriaMetrics/releases/download/${vm_version}/victoria-metrics-linux-arm64-${vm_version}.tar.gz"
    local vm_archive="/tmp/victoria-metrics.tar.gz"
    local vm_service_file="/etc/systemd/system/victoriametrics.service"

    # Check if correct version is already installed
    if [[ -f "$vm_binary" ]] && "$vm_binary" -version | grep -q "$vm_version"; then
         log_message "INFO" "VictoriaMetrics version $vm_version already installed."
    else
        log_message "INFO" "Downloading VictoriaMetrics from $vm_url"
        wget -O "$vm_archive" "$vm_url" || { log_message "ERROR" "Failed to download VictoriaMetrics."; exit 1; }

        log_message "INFO" "Extracting VictoriaMetrics..."
        # Extract directly to /usr/local/bin/ (or a temp location first)
        # The binary inside the archive is typically just 'victoria-metrics-prod'
        tar xzf "$vm_archive" -C /usr/local/bin/ victoria-metrics-prod || { log_message "ERROR" "Failed to extract VictoriaMetrics binary."; exit 1; }
        # Ensure correct name if archive structure changes
        # mv /usr/local/bin/victoria-metrics-prod-something "$vm_binary" # Adjust if needed

        chmod +x "$vm_binary"
        rm "$vm_archive"
        log_message "INFO" "VictoriaMetrics binary installed at $vm_binary"
        "$vm_binary" -version # Log the installed version
    fi

    # Create dedicated user and group if they don't exist
    if ! getent group "$vm_group" > /dev/null; then
        log_message "INFO" "Creating group '$vm_group'..."
        groupadd -r "$vm_group" || { log_message "ERROR" "Failed to create group $vm_group"; exit 1; }
    fi
    if ! getent passwd "$vm_user" > /dev/null; then
        log_message "INFO" "Creating user '$vm_user'..."
        useradd -r -g "$vm_group" -d "$vm_data_dir" -s /sbin/nologin -c "VictoriaMetrics Service User" "$vm_user" || { log_message "ERROR" "Failed to create user $vm_user"; exit 1; }
    fi

    # Create data directory and set ownership
    log_message "INFO" "Ensuring data directory '$vm_data_dir' exists..."
    mkdir -p "$vm_data_dir"
    chown -R "${vm_user}:${vm_group}" "$vm_data_dir"
    chmod -R 750 "$vm_data_dir" # User rwx, Group rx, Others no access

    # Create systemd service file
    log_message "INFO" "Creating VictoriaMetrics systemd service file..."
    process_template "$TEMPLATE_DIR/victoria-metrics.service.j2" "$vm_service_file"
    chmod 644 "$vm_service_file"

    # Enable and start the service
    log_message "INFO" "Reloading systemd, enabling and starting VictoriaMetrics..."
    systemctl daemon-reload
    systemctl enable victoriametrics.service
    systemctl restart victoriametrics.service

    log_message "INFO" "VictoriaMetrics setup complete. Listening on port ${CONFIG[VICTORIA_METRICS_PORT]}."
}

setup_nodered() {
    log_message "INFO" "Setting up Node-RED..."

    # Install Node.js and Node-RED using the official script
    # This script handles Node.js installation/update based on the --node-major parameter
    local nodejs_version_major="${CONFIG[NODEJS_INSTALL_VERSION]}" # e.g., "lts", "18", "20"
    local node_red_mem_limit="${CONFIG[NODE_RED_MEMORY_LIMIT_MB]}"

    log_message "INFO" "Running Node-RED install script for Node.js version '${nodejs_version_major}'..."
    log_message "INFO" "Node-RED will run as user '$APP_USER' with memory limit ${node_red_mem_limit}MB."

    # Download and execute the script with appropriate flags
    # Run it as root, but specify the target user for the service
    bash <(curl -sL https://raw.githubusercontent.com/node-red/linux-installers/master/deb/update-nodejs-and-nodered) \
        --confirm-root \
        --confirm-install \
        --skip-pi \
        "--node-major=${nodejs_version_major}" \
        "--nodered-user=${APP_USER}" \
        "--max-old-space-size=${node_red_mem_limit}" || {
            log_message "ERROR" "Node-RED installation script failed."
            exit 1
        }

    # Wait a moment for potential background processes from the script
    sleep 5

    # --- Configure Node-RED settings.js ---
    local settings_file="$NODE_RED_DATA_DIR/settings.js"
    log_message "INFO" "Configuring Node-RED settings at $settings_file..."

    if [[ ! -f "$settings_file" ]]; then
        log_message "WARNING" "Node-RED settings file ($settings_file) not found. Node-RED might need to run once to create it."
        # Attempt to start and stop Node-RED to generate the file (may not work if service fails immediately)
        log_message "INFO" "Attempting to start Node-RED service briefly to generate settings..."
        if systemctl start nodered.service; then
             sleep 10 # Give it time to potentially write the file
             systemctl stop nodered.service
             if [[ ! -f "$settings_file" ]]; then
                  log_message "ERROR" "Failed to generate Node-RED settings file. Cannot configure admin auth."
                  exit 1
             fi
        else
             log_message "ERROR" "Failed to start Node-RED service. Cannot configure admin auth."
             exit 1
        fi
    fi

    # Ensure the settings file is owned by the application user
    chown "${APP_USER}:${APP_GROUP}" "$settings_file"

    # Check if adminAuth is already configured (idempotency)
    if grep -q "adminAuth:" "$settings_file"; then
        log_message "INFO" "Node-RED adminAuth already appears to be configured in settings.js. Skipping modification."
    else
        log_message "INFO" "Adding adminAuth configuration to settings.js..."
        # This is a tricky part: injecting Javascript code into settings.js robustly.
        # Using sed is fragile. A better way might be a small node script, but let's try sed carefully.
        # Find the 'module.exports = {' line and insert adminAuth after it.
        # WARNING: This assumes a specific structure of settings.js
        local admin_auth_block
        admin_auth_block=$(cat <<EOF

    //-- syHub Added: Enable Admin Security --//
    adminAuth: {
        type: "credentials",
        users: [{
            username: "${CONFIG[NODE_RED_USERNAME]}",
            password: "${CONFIG[NODE_RED_PASSWORD_HASH]}",
            permissions: "*"
        }],
        // To create users collection create a file using node-red-admin hash-pw command
        // To create users collection: node -e "console.log(require('bcryptjs').hashSync(process.argv[1], 8));" your-password
        // default: {
        //     permissions: "read"
        // }
    },
    //-- End syHub Added --//

EOF
        )

        # Use awk for safer insertion after 'module.exports = {'
        awk -v auth_block="$admin_auth_block" '
        /module\.exports = {/ {
            print $0;
            print auth_block;
            next;
        }
        { print $0 }
        ' "$settings_file" > "$settings_file.tmp" && mv "$settings_file.tmp" "$settings_file"

        # Alternative sed approach (more risky):
        # sed -i "/module.exports = {/a \\${admin_auth_block}" "$settings_file" # The 'a \' command appends on the next line

        # Verify insertion (simple check)
        if ! grep -q "adminAuth:" "$settings_file" || ! grep -q "${CONFIG[NODE_RED_USERNAME]}" "$settings_file"; then
            log_message "ERROR" "Failed to add adminAuth block to $settings_file correctly."
            exit 1
        fi
        log_message "INFO" "Admin authentication configured in Node-RED."
    fi

    # Install extra Node-RED nodes if needed (e.g., for specific sensors or dashboards)
    # Example: Install dashboard nodes
    # log_message "INFO" "Installing node-red-dashboard..."
    # sudo -u "$APP_USER" npm install --prefix "$NODE_RED_DATA_DIR" node-red-dashboard || log_message "WARNING" "Failed to install node-red-dashboard."
    # Example: Install MQTT nodes (usually included)
    # Example: Install VictoriaMetrics node (if one exists and is useful)


    # Ensure data directory permissions
    chown -R "${APP_USER}:${APP_GROUP}" "$NODE_RED_DATA_DIR"
    chmod -R u+rwX,g+rX,o-rwx "$NODE_RED_DATA_DIR" # User full access, group read/execute, others none

    # Restart Node-RED service to apply settings
    log_message "INFO" "Restarting Node-RED service..."
    systemctl restart nodered.service

    log_message "INFO" "Node-RED setup complete. Access UI at http://${CONFIG[HOSTNAME]}:${CONFIG[NODE_RED_PORT]}"
}

setup_dashboard() {
    log_message "INFO" "Setting up Flask Dashboard..."

    # --- Create Python Virtual Environment ---
    log_message "INFO" "Creating Python virtual environment at $VENV_DIR..."
    # Create venv as the application user
    sudo -u "$APP_USER" python3 -m venv "$VENV_DIR" || { log_message "ERROR" "Failed to create Python venv."; exit 1; }

    # --- Install Python Dependencies ---
    log_message "INFO" "Installing Python dependencies into venv..."
    # Activate venv and install packages (run pip as the app user)
    # Using --break-system-packages is generally not needed when installing into a venv
    # Use full path to pip within venv to avoid potential PATH issues
    local pip_cmd="$VENV_DIR/bin/pip"
    sudo -u "$APP_USER" "$pip_cmd" install --upgrade pip || log_message "WARNING" "Failed to upgrade pip."
    sudo -u "$APP_USER" "$pip_cmd" install \
        flask \
        gunicorn \
        paho-mqtt \
        requests \
        psutil \
        pyyaml || {
            log_message "ERROR" "Failed to install Python dependencies."; exit 1;
        }
    log_message "INFO" "Python dependencies installed."

    # --- Deploy Flask Application Code ---
    log_message "INFO" "Deploying Flask application code..."
    process_template "$TEMPLATE_DIR/flask_app.py.j2" "$DEPLOYED_FLASK_APP"
    # Set ownership for the deployed app file
    chown "${APP_USER}:${APP_GROUP}" "$DEPLOYED_FLASK_APP"
    chmod 644 "$DEPLOYED_FLASK_APP" # Readable by user/group

    # Ensure static directory exists and has correct permissions
    mkdir -p "$STATIC_DIR"
    chown -R "${APP_USER}:${APP_GROUP}" "$STATIC_DIR"
    chmod -R u+rwX,g+rX,o+rX "$STATIC_DIR" # Web server needs read access

    # --- Create systemd Service File ---
    log_message "INFO" "Creating Flask Dashboard systemd service file..."
    process_template "$TEMPLATE_DIR/flask-dashboard.service.j2" "/etc/systemd/system/flask-dashboard.service"
    chmod 644 "/etc/systemd/system/flask-dashboard.service"

    # --- Enable and Start Service ---
    log_message "INFO" "Reloading systemd, enabling and starting Flask Dashboard service..."
    systemctl daemon-reload
    systemctl enable flask-dashboard.service
    systemctl restart flask-dashboard.service

    log_message "INFO" "Flask Dashboard setup complete. Access at http://${CONFIG[HOSTNAME]}:${CONFIG[DASHBOARD_PORT]}"
}

# --- Main Action Functions ---

action_setup() {
    log_message "INFO" "Starting syHub Setup..."
    check_internet
    setup_dependencies # Installs yq, then sets up proper logging
    load_all_config    # Load config after yq is available
    setup_network
    setup_mqtt
    setup_victoriametrics
    setup_nodered
    setup_dashboard
    log_message "INFO" "--- syHub Setup Completed Successfully ---"
    action_status # Show status after setup
}

action_update() {
    # Primarily updates system packages and potentially re-runs specific setups if needed
    setup_logging "update"
    log_message "INFO" "Starting syHub Update..."
    check_internet

    log_message "INFO" "Updating system packages..."
    apt-get update -y && apt-get upgrade -y
    apt-get autoremove -y && apt-get clean

    # Optional: Re-run specific setup steps if components need updating based on config changes
    # Example: Re-run Node-RED setup if Node.js version changed (though installer handles this)
    # Example: Re-download VictoriaMetrics if version changed in config
    # load_all_config # Reload config to check versions
    # compare versions and re-run setup_victoriametrics if needed...
    # compare versions and re-run setup_nodered if needed...

    # Optional: Pull latest version of AP+STA script
    local ap_sta_script_dir="/opt/AP_STA_RPI_SAME_WIFI_CHIP"
    if [[ -d "$ap_sta_script_dir/.git" ]]; then
         log_message "INFO" "Updating AP_STA_RPI_SAME_WIFI_CHIP script..."
        (cd "$ap_sta_script_dir" && git pull)
        # Consider re-running its install script if significant changes occurred? Risky.
    fi

    # Optional: Update Node-RED nodes
    # log_message "INFO" "Updating Node-RED nodes..."
    # sudo -u "$APP_USER" npm update --prefix "$NODE_RED_DATA_DIR"

    # Optional: Update Python dependencies
    # log_message "INFO" "Updating Python dependencies..."
    # local pip_cmd="$VENV_DIR/bin/pip"
    # sudo -u "$APP_USER" "$pip_cmd" install --upgrade -r <requirements_file_if_used>

    # Restart services to ensure they use latest libraries/configs
    log_message "INFO" "Restarting syHub services..."
    systemctl restart mosquitto victoriametrics nodered flask-dashboard avahi-daemon hostapd dnsmasq

    log_message "INFO" "--- syHub Update Completed ---"
    action_status
}

action_purge() {
    # Ensure logging is set up for this action
    setup_logging "purge"
    # Load config to get paths and the configure_network flag
    # Need to handle case where config or yq might be missing if purge is run after partial failure
    if ! command -v yq &> /dev/null || [[ ! -f "$CONFIG_FILE" ]]; then
         log_message "ERROR" "Cannot load config ($CONFIG_FILE) or yq is missing. Full purge cannot proceed reliably."
         log_message "ERROR" "Manual cleanup required. Stopping known services..."
         systemctl stop flask-dashboard nodered victoriametrics mosquitto hostapd dnsmasq avahi-daemon || true # Ignore errors if already stopped
         exit 1
    fi
    load_all_config # Load all config values

    log_message "WARNING" "--- Starting syHub Purge ---"
    log_message "WARNING" "This will stop services, remove configuration, and potentially delete data!"
    read -p "Are you absolutely sure you want to purge syHub? (yes/N): " confirmation
    if [[ "${confirmation,,}" != "yes" ]]; then
        log_message "INFO" "Purge cancelled."
        exit 0
    fi

    log_message "INFO" "Stopping and disabling syHub services..."
    # Stop core syHub services + network components potentially managed
    systemctl stop flask-dashboard nodered victoriametrics mosquitto hostapd dnsmasq avahi-daemon || log_message "WARNING" "Some services might have already been stopped."
    systemctl disable flask-dashboard nodered victoriametrics mosquitto hostapd dnsmasq || log_message "WARNING" "Some services might have already been disabled."
    # Stop wpa_supplicant service if running on wlan0 (often managed automatically)
    # systemctl stop wpa_supplicant@wlan0.service || true # Ignore errors

    log_message "INFO" "Removing syHub systemd service files..."
    rm -f /etc/systemd/system/flask-dashboard.service \
          /etc/systemd/system/nodered.service \
          /etc/systemd/system/victoriametrics.service
    systemctl daemon-reload

    # --- Conditionally Remove Network Configs ---
    if [[ "${CONFIG[CONFIGURE_NETWORK],,}" == "true" ]]; then
        log_message "INFO" "Removing network configuration files installed by syHub AP+STA setup..."
        rm -f /etc/dnsmasq.d/01-syhub-ap.conf
        rm -f /bin/manage-ap0-iface.sh
        rm -f /bin/rpi-wifi.sh
        rm -f /etc/hostapd/hostapd.conf
        # Restore backup of /etc/default/hostapd if it exists? Or remove our line?
        # sed -i '/DAEMON_CONF="\/etc\/hostapd\/hostapd.conf"/d' /etc/default/hostapd # Example removal
        rm -f /etc/wpa_supplicant/wpa_supplicant.conf
        rm -f /etc/udev/rules.d/70-persistent-net.rules

        read -p "Restore default /etc/network/interfaces (y/N)? (Warning: This removes syHub config): " restore_interfaces
        if [[ "${restore_interfaces,,}" == "y" ]]; then
             log_message "INFO" "Restoring default /etc/network/interfaces..."
             # Create a minimal default config
             cat << EOF > /etc/network/interfaces
source-directory /etc/network/interfaces.d
auto lo
iface lo inet loopback
EOF
             # Recommend using dhcpcd for primary interface management
             log_message "INFO" "Consider ensuring dhcpcd is enabled for standard network management."
        else
             log_message "INFO" "Skipping modification of /etc/network/interfaces."
        fi

        log_message "INFO" "Removing AP+STA cron job and log directory..."
        (crontab -l 2>/dev/null | grep -v "/bin/manage-ap0-iface.sh" | grep -v "/bin/rpi-wifi.sh") | crontab - || log_message "WARNING" "Failed to remove AP+STA cron jobs."
        rm -f /tmp/syhub_ap0_manage.lock

        read -p "Delete AP+STA log directory (/var/log/ap_sta_wifi)? (yes/N): " del_apsta_logs
        if [[ "${del_apsta_logs,,}" == "yes" ]]; then
            log_message "INFO" "Deleting AP+STA log directory..."
            rm -rf /var/log/ap_sta_wifi
        else
            log_message "INFO" "Skipping AP+STA log directory deletion."
        fi
    else
         log_message "INFO" "Skipping removal of network configuration files (configure_network was false)."
    fi
    # --- End Conditional Removal ---

    # Remove other syHub configs unconditionally
    log_message "INFO" "Removing other syHub configuration files..."
    rm -f /etc/mosquitto/conf.d/syhub.conf
    rm -f /etc/mosquitto/passwd
    rm -f /etc/avahi/services/syhub.service

    # --- Remove Data Directories (with prompts) ---
    log_message "INFO" "Removing VictoriaMetrics binary and data..."
    rm -f /usr/local/bin/victoria-metrics-prod
    read -p "Delete VictoriaMetrics data directory (${CONFIG[VICTORIA_METRICS_DATA_DIRECTORY]})? (yes/N): " del_vm_data
    if [[ "${del_vm_data,,}" == "yes" ]]; then
        log_message "INFO" "Deleting VictoriaMetrics data directory..."
        rm -rf "${CONFIG[VICTORIA_METRICS_DATA_DIRECTORY]}"
    else
        log_message "INFO" "Skipping VictoriaMetrics data directory deletion."
    fi
    # Delete VM user/group
    local vm_user="${CONFIG[VICTORIA_METRICS_SERVICE_USER]}"
    local vm_group="${CONFIG[VICTORIA_METRICS_SERVICE_GROUP]}"
    if getent passwd "$vm_user" > /dev/null; then userdel "$vm_user" || log_message "WARNING" "Failed to delete user $vm_user."; fi
    if getent group "$vm_group" > /dev/null; then if [[ -z $(getent group "$vm_group" | cut -d: -f4) ]]; then groupdel "$vm_group" || log_message "WARNING" "Failed to delete group $vm_group."; else log_message "WARNING" "Group $vm_group not deleted because it might not be empty."; fi fi

    log_message "INFO" "Removing Node-RED data..."
    read -p "Delete Node-RED data directory (${NODE_RED_DATA_DIR})? (yes/N): " del_nr_data
    if [[ "${del_nr_data,,}" == "yes" ]]; then
        log_message "INFO" "Deleting Node-RED data directory..."
        rm -rf "$NODE_RED_DATA_DIR"
    else
        log_message "INFO" "Skipping Node-RED data directory deletion."
    fi

    # --- Remove Application Base Directory ---
    log_message "INFO" "Removing application base directory..."
    read -p "Delete application base directory (${SYHUB_BASE_DIR})? (yes/N): " del_base_dir
    if [[ "${del_base_dir,,}" == "yes" ]]; then
        log_message "INFO" "Deleting application base directory..."
        rm -rf "$SYHUB_BASE_DIR"
    else
        log_message "INFO" "Skipping application base directory deletion."
    fi

    # --- Reset Hostname ---
    log_message "INFO" "Resetting hostname to default (raspberrypi)..."
    hostnamectl set-hostname raspberrypi
    # Remove or modify the 127.0.1.1 line related to our hostname
    if grep -q "${CONFIG[HOSTNAME]}" /etc/hosts; then
         sed -i "/127.0.1.1.*${CONFIG[HOSTNAME]}/d" /etc/hosts
    fi

    log_message "WARNING" "--- syHub Purge Completed ---"
    log_message "WARNING" "Review network configurations in /etc/ and /var/log/ for any remaining artifacts."
    log_message "WARNING" "A system reboot is strongly recommended."
}

action_backup() {
    setup_logging "backup"
    load_all_config # Need config for paths

    log_message "INFO" "Starting syHub Backup..."
    local backup_parent_dir="${CONFIG[BACKUP_DIRECTORY]}"
    # Handle relative vs absolute backup path
    if [[ "$backup_parent_dir" != /* ]]; then
        backup_parent_dir="$SYHUB_BASE_DIR/$backup_parent_dir"
    fi
    mkdir -p "$backup_parent_dir"

    local timestamp
    timestamp=$(date '+%Y%m%d_%H%M%S')
    local backup_filename="syhub_backup_${timestamp}.tar.gz"
    local backup_filepath="$backup_parent_dir/$backup_filename"

    log_message "INFO" "Creating backup archive: $backup_filepath"

    # List of files and directories to back up
    local backup_items=(
        "$CONFIG_FILE"                               # Main config
        "$SYHUB_BASE_DIR/scripts"                    # Scripts
        "$SYHUB_BASE_DIR/static"                     # Static dashboard files
        "$SYHUB_BASE_DIR/templates"                  # Templates
        # Deployed app file (might be same as template if not processed)
        "$DEPLOYED_FLASK_APP"
        # System configs (copy them temporarily to include?)
        "/etc/hostapd/hostapd.conf"
        "/etc/dnsmasq.d/01-syhub-ap.conf"
        "/etc/mosquitto/conf.d/syhub.conf"
        "/etc/mosquitto/passwd"
        "/etc/avahi/services/syhub.service"
        "/etc/systemd/system/flask-dashboard.service"
        "/etc/systemd/system/nodered.service"
        "/etc/systemd/system/victoriametrics.service"
        # Node-RED Data
        "$NODE_RED_DATA_DIR"
        # Optional: VictoriaMetrics Data (can be very large!)
        # "${CONFIG[VICTORIA_METRICS_DATA_DIRECTORY]}"
    )

    # Check if VictoriaMetrics data backup is desired (prompt user?)
    local include_vm_data=false
    # read -p "Include VictoriaMetrics data in backup (can be large)? (yes/N): " include_vm_q
    # if [[ "${include_vm_q,,}" == "yes" ]]; then
    #    include_vm_data=true
    #    backup_items+=("${CONFIG[VICTORIA_METRICS_DATA_DIRECTORY]}")
    # fi

    # Create the archive
    # Use --ignore-failed-read to avoid errors if optional files are missing
    # Use --absolute-names to store full paths OR use -C to change directory
    # Using -C is generally better for restore portability
    # tar -czf "$backup_filepath" --ignore-failed-read "${backup_items[@]}" || {
    #    log_message "ERROR" "Backup failed during tar creation."
    #    rm -f "$backup_filepath" # Clean up partial archive
    #    exit 1
    # }

    # Using -C for relative paths in archive (more complex for system files)
    # Create a temporary directory for staging system files?
    local temp_backup_dir
    temp_backup_dir=$(mktemp -d)
    mkdir -p "$temp_backup_dir/syhub_config"
    mkdir -p "$temp_backup_dir/system_config/etc/hostapd"
    mkdir -p "$temp_backup_dir/system_config/etc/dnsmasq.d"
    mkdir -p "$temp_backup_dir/system_config/etc/mosquitto/conf.d"
    mkdir -p "$temp_backup_dir/system_config/etc/avahi/services"
    mkdir -p "$temp_backup_dir/system_config/etc/systemd/system"
    mkdir -p "$temp_backup_dir/user_data"

    log_message "INFO" "Staging files for backup..."
    # Copy syHub project files
    cp -a "$CONFIG_FILE" "$SYHUB_BASE_DIR/scripts" "$SYHUB_BASE_DIR/static" "$SYHUB_BASE_DIR/templates" "$DEPLOYED_FLASK_APP" "$temp_backup_dir/syhub_config/"
    # Copy system files
    cp -a /etc/hostapd/hostapd.conf "$temp_backup_dir/system_config/etc/hostapd/" || log_message "WARNING" "hostapd.conf not found."
    cp -a /etc/dnsmasq.d/01-syhub-ap.conf "$temp_backup_dir/system_config/etc/dnsmasq.d/" || log_message "WARNING" "dnsmasq config not found."
    cp -a /etc/mosquitto/conf.d/syhub.conf "$temp_backup_dir/system_config/etc/mosquitto/conf.d/" || log_message "WARNING" "mosquitto config not found."
    cp -a /etc/mosquitto/passwd "$temp_backup_dir/system_config/etc/mosquitto/" || log_message "WARNING" "mosquitto passwd not found."
    cp -a /etc/avahi/services/syhub.service "$temp_backup_dir/system_config/etc/avahi/services/" || log_message "WARNING" "avahi service not found."
    cp -a /etc/systemd/system/flask-dashboard.service "$temp_backup_dir/system_config/etc/systemd/system/" || log_message "WARNING" "flask service file not found."
    cp -a /etc/systemd/system/nodered.service "$temp_backup_dir/system_config/etc/systemd/system/" || log_message "WARNING" "nodered service file not found."
    cp -a /etc/systemd/system/victoriametrics.service "$temp_backup_dir/system_config/etc/systemd/system/" || log_message "WARNING" "vm service file not found."
    # Copy Node-RED data
    cp -a "$NODE_RED_DATA_DIR" "$temp_backup_dir/user_data/" || log_message "WARNING" "Node-RED data dir not found or failed to copy."
    # Optionally copy VM data
    # if $include_vm_data; then ... cp -a ... "$temp_backup_dir/user_data/"

    log_message "INFO" "Creating archive from staged files..."
    tar -czf "$backup_filepath" -C "$temp_backup_dir" . || {
        log_message "ERROR" "Backup failed during tar creation."
        rm -f "$backup_filepath" # Clean up partial archive
        rm -rf "$temp_backup_dir" # Clean up temp dir
        exit 1
    }

    rm -rf "$temp_backup_dir" # Clean up temp dir

    # Set permissions? Backup file owned by root.
    chown "${APP_USER}:${APP_GROUP}" "$backup_filepath" || log_message "WARNING" "Could not change ownership of backup file."
    chmod 640 "$backup_filepath" # Readable by user/group

    log_message "INFO" "--- Backup Created Successfully: $backup_filepath ---"

    # Optional: Prune old backups
    log_message "INFO" "Pruning old backups (keeping last 5)..."
    ls -1t "$backup_parent_dir"/syhub_backup_*.tar.gz | tail -n +6 | xargs --no-run-if-empty rm
    log_message "INFO" "Old backups pruned."
}

action_status() {
    # Don't redirect status output to log file, show directly
    # exec >&1
    # exec 2>&1
    echo "--- syHub Status ---"
    echo "Time: $(date)"
    echo "Hostname: $(hostname)"
    echo "User: $APP_USER"
    echo "Base Directory: $SYHUB_BASE_DIR"
    echo ""

    echo "[Network]"
    ip addr show wlan0 | grep -E "inet |ssid" || echo " wlan0: No IP/SSID info found."
    ip addr show "${CONFIG[WIFI_AP_INTERFACE]:-uap0}" | grep "inet " || echo " ${CONFIG[WIFI_AP_INTERFACE]:-uap0}: No IP info found."
    echo "AP_STA Script Dir: /opt/AP_STA_RPI_SAME_WIFI_CHIP"
    echo ""

    echo "[Services]"
    local services=(
        hostapd
        dnsmasq
        avahi-daemon
        mosquitto
        victoriametrics
        nodered
        flask-dashboard
    )
    for service in "${services[@]}"; do
        # Check if service file exists before querying status
        if [[ -f "/etc/systemd/system/${service}.service" || -f "/lib/systemd/system/${service}.service" ]]; then
             systemctl is-active --quiet "$service" && echo " $service: active" || systemctl is-active "$service" | xargs echo " $service:"
        else
             echo " $service: (service file not found)"
        fi

    done
    echo ""

    echo "[Endpoints (check from connected device)]"
    if [[ -n "${CONFIG[HOSTNAME]}" ]]; then
        echo " Dashboard: http://${CONFIG[HOSTNAME]}:${CONFIG[DASHBOARD_PORT]}"
        echo " Node-RED: http://${CONFIG[HOSTNAME]}:${CONFIG[NODE_RED_PORT]}"
        echo " MQTT URI: mqtt://${CONFIG[HOSTNAME]}:${CONFIG[MQTT_PORT]}"
        echo " VictoriaMetrics: http://${CONFIG[HOSTNAME]}:${CONFIG[VICTORIA_METRICS_PORT]}"
    else
         echo " (Config not fully loaded - cannot show endpoints)"
    fi
    echo ""

     echo "[Resource Usage]"
     echo -n " CPU Load: " ; top -bn1 | grep "load average:" | awk '{printf "%.2f, %.2f, %.2f\n", $10,$11,$12}'
     echo -n " Memory: " ; free -h | grep Mem | awk '{printf "%s/%s (Used: %s)\n", $3,$2,$7}'
     echo -n " Disk (/): " ; df -h / | awk 'NR==2 {print $5 " full (" $3 "/" $2 ")"}'
     echo -n " CPU Temp: " ; vcgencmd measure_temp 2>/dev/null || echo "N/A"
     echo ""

    echo "--- End Status ---"
}


# --- Main Script Logic ---

# Ensure config directory exists early, needed for yq check
mkdir -p "$(dirname "$CONFIG_FILE")"

# Default action is 'status' if no argument given
ACTION="${1:-status}"

# Load config early ONLY for status action to show endpoints.
# For other actions, dependencies (like yq) must be installed first.
if [[ "$ACTION" == "status" ]]; then
    if command -v yq &> /dev/null && [[ -f "$CONFIG_FILE" ]]; then
         declare -gA CONFIG # Make it global for status func
         load_all_config || log_message "WARNING" "Failed to load config for status, some info may be missing."
    else
         echo "WARNING: yq not found or config file missing. Status information will be limited."
    fi
    action_status
    exit 0
fi


# For setup, update, purge, backup - run the respective function
case "$ACTION" in
    setup)
        action_setup
        ;;
    update)
        setup_logging "update" # Need logging setup for this action
        load_all_config # Update needs config
        action_update
        ;;
    purge)
        setup_logging "purge" # Need logging setup
        load_all_config # Purge needs config paths (e.g., data dirs)
        action_purge
        ;;
    backup)
        setup_logging "backup" # Need logging setup
        load_all_config # Backup needs config paths
        action_backup
        ;;
    *)
        echo "Usage: sudo bash $0 {setup|update|purge|backup|status}"
        exit 1
        ;;
esac

exit 0