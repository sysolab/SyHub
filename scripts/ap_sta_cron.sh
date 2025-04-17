#!/bin/bash
# /home/<YOUR_USER>/syhub/scripts/ap_sta_cron.sh
# Modified script to set up AP+STA connection check cron jobs
# Based on https://github.com/MkLHX/AP_STA_RPI_SAME_WIFI_CHIP
# Modified by syHub setup script to use config.yml via environment variables

# --- Configuration Source: Environment Variables (Set by syhub.sh) ---
# SYHUB_CRON_LOG_FILE_AP0_MGNT # Full path for ap0 management log
# SYHUB_CRON_LOG_FILE_ON_BOOT  # Full path for on boot script log

# --- Safety ---
set -o errexit
set -o pipefail
set -o nounset

# No color codes or complex logging here
_logger() {
    echo "[ap_sta_cron.sh] ${1}"
}

# --- Validate Required Environment Variables ---
if [[ -z "${SYHUB_CRON_LOG_FILE_AP0_MGNT:-}" || -z "${SYHUB_CRON_LOG_FILE_ON_BOOT:-}" ]]; then
    _logger "ERROR: Missing required environment variables for cron log paths."
    _logger "Ensure SYHUB_CRON_LOG_FILE_AP0_MGNT and SYHUB_CRON_LOG_FILE_ON_BOOT are set."
    exit 1
fi

# --- Check Prerequisites (Basic) ---
if [ $(id -u) != 0 ]; then
    _logger "ERROR: This script must be run as root."
    exit 1
fi
# Crontab initialization check removed - handled by main syhub.sh


# Define log files using environment variables
AP0_MGNT_LOG="${SYHUB_CRON_LOG_FILE_AP0_MGNT}"
ON_BOOT_LOG="${SYHUB_CRON_LOG_FILE_ON_BOOT}"


# --- Add Cron Jobs ---
_logger "Adding AP+STA cron jobs to root's crontab..."

# Get current crontab, append new jobs, then apply
# Use a temporary file for atomic update
cron_jobs_tmp=$(mktemp)
crontab -l 2>/dev/null > "$cron_jobs_tmp" # Get existing crontab (or empty if none)

# Add the ap0 management cron job if it doesn't exist
# Uses flock to prevent multiple instances running simultaneously
CRON_JOB_AP0_MANAGE='* * * * * root flock -n /tmp/syhub_ap0_manage.lock -c "/bin/bash /bin/manage-ap0-iface.sh >> '"$AP0_MGNT_LOG"' 2>&1"'
if ! grep -q "/bin/manage-ap0-iface.sh" "$cron_jobs_tmp"; then
    _logger "Adding cron job for ap0 interface management..."
    echo "# syHub: Start hostapd when ap0 already exists" >> "$cron_jobs_tmp"
    echo "$CRON_JOB_AP0_MANAGE" >> "$cron_jobs_tmp"
else
    _logger "Cron job for ap0 interface management already exists."
    # Optional: Replace existing line if template changes?
    # sed -i "s|.*\/bin\/manage-ap0-iface\.sh.*|$CRON_JOB_AP0_MANAGE|" "$cron_jobs_tmp"
fi

# Add the @reboot cron job to run rpi-wifi.sh if it doesn't exist
CRON_JOB_ON_BOOT='@reboot sleep 20 && /bin/bash /bin/rpi-wifi.sh >> '"$ON_BOOT_LOG"' 2>&1'
if ! grep -q "/bin/rpi-wifi.sh" "$cron_jobs_tmp"; then
    _logger "Adding @reboot cron job for rpi-wifi startup script..."
    echo "# syHub: On boot start AP + STA config" >> "$cron_jobs_tmp"
    echo "$CRON_JOB_ON_BOOT" >> "$cron_jobs_tmp"
else
    _logger "@reboot cron job for rpi-wifi startup script already exists."
    # Optional: Replace existing line?
    # sed -i "s|.*\/bin\/rpi-wifi\.sh.*|$CRON_JOB_ON_BOOT|" "$cron_jobs_tmp"
fi

# Apply the updated crontab
crontab "$cron_jobs_tmp" || {
    _logger "ERROR: Failed to apply updated crontab."
    rm "$cron_jobs_tmp" # Clean up temp file
    exit 1
}
_logger "Crontab updated successfully."

# Clean up temporary file
rm "$cron_jobs_tmp"

_logger "ap_sta_cron.sh finished."