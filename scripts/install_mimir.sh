#!/bin/bash
# User data script for Grafana Mimir instance
# This script installs and configures Grafana Mimir in monolithic mode using S3 for storage.

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Variables passed from Terraform ---
MIMIR_VERSION="${mimir_version}"
MIMIR_ZIP_FILENAME="${mimir_zip_filename}"
MIMIR_BINARY_NAME="${mimir_binary_name}"
MIMIR_S3_BUCKET="${mimir_s3_bucket}"
AWS_REGION="${aws_region}"

# --- Logging ---
exec > >(tee /var/log/cloud-init-output.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "--- Starting Mimir User Data Script ---"
echo "Timestamp: $(date)"
echo "Mimir Version to install: $MIMIR_VERSION"
echo "Target S3 Bucket: $MIMIR_S3_BUCKET"
echo "AWS Region: $AWS_REGION"

# --- System Update and Dependencies ---
echo "Updating system packages and installing dependencies..."
sudo dnf update -y
sudo dnf install -y wget unzip tar gzip

# --- Download and Install Mimir ---
echo "Downloading Grafana Mimir version $MIMIR_VERSION..."
cd /tmp
# Mimir releases might be named slightly differently (e.g., just 'mimir'), adjust URL if needed.
wget --quiet "https://github.com/grafana/mimir/releases/download/${MIMIR_VERSION}/${MIMIR_ZIP_FILENAME}" -O ${MIMIR_ZIP_FILENAME}

echo "Installing Mimir..."
unzip -o ${MIMIR_ZIP_FILENAME}
# The binary inside might just be 'mimir', check the release assets. Assuming standard name for now.
sudo mv ./${MIMIR_BINARY_NAME} /usr/local/bin/mimir
sudo chmod +x /usr/local/bin/mimir
rm -f ${MIMIR_ZIP_FILENAME}
echo "Mimir binary installed at $(which mimir)"
mimir --version # Verify installation

# --- Create Mimir User and Directories (Optional but Recommended) ---
# sudo groupadd --system mimir || echo "Group 'mimir' already exists."
# sudo useradd --system --no-create-home --gid mimir mimir || echo "User 'mimir' already exists."
# Create directories needed by Mimir components (config, data, WAL, etc.)
# Using /data/mimir as the base for runtime data.
# sudo mkdir -p /etc/mimir /data/mimir/tsdb /data/mimir/compactor /data/mimir/ruler /data/mimir/alertmanager /data/mimir/wal
# sudo chown -R mimir:mimir /etc/mimir /data/mimir
# sudo chmod -R 750 /etc/mimir /data/mimir

# --- Create Mimir Configuration ---
# Using root user and /tmp paths for simplicity. Use dedicated user and /data/mimir for production.
sudo mkdir -p /etc/mimir /tmp/mimir/tsdb /tmp/mimir/compactor /tmp/mimir/ruler /tmp/mimir/alertmanager /tmp/mimir/wal

echo "Creating Mimir configuration file at /etc/mimir/mimir-config.yaml..."
cat <<EOF | sudo tee /etc/mimir/mimir-config.yaml
# Run Mimir in monolithic mode (all components in one process).
target: all

# WARNING: Authentication and multi-tenancy are disabled for simplicity.
# Enable 'auth_enabled: true' and configure 'multitenancy_enabled: true'
# along with 'auth' block (e.g., type: basic) and tenant ID headers for production.
auth_enabled: false
multitenancy_enabled: false
# server_http_listen_address: 0.0.0.0 # Default, listens on all interfaces

server:
  http_listen_port: 9009 # Port for Mimir API (writes, queries)
  grpc_listen_port: 9095 # Port for internal gRPC communication
  log_level: info

# Distributor configuration (handles incoming writes).
distributor:
  ring:
    instance_addr: 127.0.0.1 # Use loopback address for memberlist KV in monolithic mode
    kvstore:
      store: memberlist # Use memberlist for simple KV store

# Ingester configuration (stores recent data, writes to long-term storage).
ingester:
  ring:
    instance_addr: 127.0.0.1
    kvstore:
      store: memberlist
    replication_factor: 1 # Single instance setup
  # WAL (Write Ahead Log) for durability.
  wal_enabled: true
  wal_dir: /tmp/mimir/wal # Directory for WAL files (use persistent local storage)

# Common configuration for components using the ring/KV store.
common:
  # Storage configuration using S3 as the backend.
  storage:
    backend: s3
    s3:
      bucket_name: ${MIMIR_S3_BUCKET} # S3 bucket name from Terraform
      region: ${AWS_REGION}         # AWS region from Terraform
      # endpoint: s3.${AWS_REGION}.amazonaws.com # Usually not needed
      # sse_encryption: false # Enable SSE for production
      # access_key_id/secret_access_key handled by IAM role.
  # Replication factor for ingester data.
  replication_factor: 1

# Blocks storage configuration (for TSDB blocks in S3).
blocks_storage:
  backend: s3 # Use S3 for long-term block storage
  # TSDB configuration (local storage for head block, WAL).
  tsdb:
    dir: /tmp/mimir/tsdb # Local directory for recent blocks/head data
    # retention_period: 0 # Default: keep blocks indefinitely in storage
    # ship_interval: 1m   # How often to check if blocks need shipping to S3
  # S3 configuration for blocks (inherits from common.storage.s3).
  s3:
    # bucket_name: inherits
    # Optional: Add a prefix within the bucket for blocks
    # dir: blocks/

# Alertmanager storage configuration (if using Mimir's built-in Alertmanager).
alertmanager_storage:
  backend: s3
  s3: # Inherits from common.storage.s3
    # bucket_name: inherits
    # Optional: Add a prefix within the bucket for Alertmanager state
    # dir: alertmanager/

# Ruler storage configuration (for recording/alerting rules).
ruler_storage:
  backend: s3
  s3: # Inherits from common.storage.s3
    # bucket_name: inherits
    # Optional: Add a prefix within the bucket for rules
    # dir: ruler/

# Compactor configuration (merges blocks in S3).
compactor:
  data_dir: /tmp/mimir/compactor # Local temporary directory for compaction work
  sharding_ring:
    kvstore:
      store: memberlist # Use memberlist for compactor coordination

# Store-gateway configuration (reads blocks from S3 for queries).
store_gateway:
  sharding_ring:
    kvstore:
      store: memberlist

# Memberlist configuration (used by various components for discovery).
memberlist:
  # No other members to join in monolithic mode.
  join_members: []
  # bind_port: 7946 # Default memberlist port

# Optional: Configure limits per tenant ('anonymous'/'fake' tenant if auth disabled).
# limits:
#   ingestion_rate: 100000 # samples/sec
#   ingestion_burst_size: 500000
#   max_label_names_per_series: 30
#   max_global_series_per_user: 5000000
#   # ... other limits
EOF

# Validate the configuration file (optional)
echo "Validating Mimir configuration..."
sudo /usr/local/bin/mimir --config.file=/etc/mimir/mimir-config.yaml --check.config || echo "Mimir config validation failed (continuing...)"

# --- Create systemd Service File ---
echo "Creating systemd service file for Mimir at /etc/systemd/system/mimir.service..."
cat <<EOF | sudo tee /etc/systemd/system/mimir.service
[Unit]
Description=Grafana Mimir Time Series Database
Documentation=https://grafana.com/docs/mimir/latest/
Wants=network-online.target
After=network-online.target

[Service]
# User=mimir # Use dedicated user if created
# Group=mimir # Use dedicated group if created
User=root # Running as root for simplicity
Group=root # Running as root for simplicity
WorkingDirectory=/etc/mimir

# Run Mimir with the specified configuration file.
ExecStart=/usr/local/bin/mimir -config.file=/etc/mimir/mimir-config.yaml
Restart=on-failure
RestartSec=5s

# Optional: Redirect stdout/stderr to syslog
# StandardOutput=syslog
# StandardError=syslog
# SyslogIdentifier=mimir

# Optional: Resource limits
# LimitNOFILE=1048576
# LimitNPROC=8192
# LimitCORE=infinity

[Install]
WantedBy=multi-user.target
EOF

# --- Enable and Start Mimir Service ---
echo "Reloading systemd daemon, enabling and starting Mimir service..."
sudo systemctl daemon-reload
sudo systemctl enable mimir.service
sudo systemctl start mimir.service
sudo systemctl status mimir.service --no-pager # Check status

echo "--- Mimir User Data Script Finished ---"
echo "Timestamp: $(date)"
