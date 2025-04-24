#!/bin/bash
# User data script for Grafana OSS instance
# This script installs and configures Grafana OSS using the official YUM repository.

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Variables passed from Terraform ---
GRAFANA_VERSION="${grafana_version}" # e.g., "10.4.2" or "latest"

# --- Logging ---
exec > >(tee /var/log/cloud-init-output.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "--- Starting Grafana User Data Script ---"
echo "Timestamp: $(date)"
echo "Grafana Version to install: $$GRAFANA_VERSION"

# --- System Update ---
echo "Updating system packages..."
sudo dnf update -y
sudo dnf install -y yum-utils # Needed for yum-config-manager

# --- Add Grafana YUM Repository ---
echo "Adding Grafana YUM repository..."
# Create the repo file
sudo tee /etc/yum.repos.d/grafana.repo << EOF
[grafana]
name=grafana
baseurl=https://packages.grafana.com/oss/rpm
repo_gpgcheck=1
enabled=1
gpgcheck=1
gpgkey=https://packages.grafana.com/gpg.key
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
EOF

# Import the GPG key
# sudo rpm --import https://packages.grafana.com/gpg.key # Often done automatically by dnf/yum

# --- Install Grafana ---
# Determine package name based on version variable
if [[ "$$GRAFANA_VERSION" == "latest" ]]; then
  GRAFANA_PACKAGE="grafana"
  echo "Installing latest Grafana OSS..."
else
  # Append the version and release (usually '-1') for specific version install
  GRAFANA_PACKAGE="grafana-$${GRAFANA_VERSION}-1"
   echo "Installing Grafana OSS version $${GRAFANA_VERSION}..."
fi

# Install the specified Grafana package
sudo dnf install -y "$$GRAFANA_PACKAGE"

# --- Start and Enable Grafana Service ---
echo "Reloading systemd daemon, enabling and starting Grafana service..."
sudo systemctl daemon-reload
sudo systemctl enable grafana-server.service # Enable Grafana to start on boot
sudo systemctl start grafana-server.service  # Start Grafana immediately
sudo systemctl status grafana-server.service --no-pager # Check status

echo "Grafana Installation Complete."
echo "Access Grafana UI at http://<PUBLIC_IP>:3000"
echo "Default login: admin / admin (change on first login)"
echo "--- Grafana User Data Script Finished ---"
echo "Timestamp: $(date)"
