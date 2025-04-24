#!/bin/bash
# User data script for Grafana Loki instance
# This script installs and configures Grafana Loki in monolithic mode using S3 for storage.

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Variables passed from Terraform ---
LOKI_VERSION="${loki_version}"
LOKI_ZIP_FILENAME="${loki_zip_filename}"
LOKI_BINARY_NAME="${loki_binary_name}"
LOKI_S3_BUCKET="${loki_s3_bucket}"
AWS_REGION="${aws_region}"

# --- Logging ---
exec > >(tee /var/log/cloud-init-output.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "--- Starting Loki User Data Script ---"
echo "Timestamp: $(date)"
echo "Loki Version to install: $$LOKI_VERSION"
echo "Target S3 Bucket: $$LOKI_S3_BUCKET"
echo "AWS Region: $$AWS_REGION"

# --- System Update and Dependencies ---
echo "Updating system packages and installing dependencies..."
sudo dnf update -y
sudo dnf install -y wget unzip tar gzip

# --- Download and Install Loki ---
echo "Downloading Grafana Loki version $$LOKI_VERSION..."
cd /tmp
wget --quiet "https://github.com/grafana/loki/releases/download/$${LOKI_VERSION}/$${LOKI_ZIP_FILENAME}" -O $${LOKI_ZIP_FILENAME}

echo "Installing Loki..."
unzip -o $${LOKI_ZIP_FILENAME}
sudo mv ./$${LOKI_BINARY_NAME} /usr/local/bin/loki
sudo chmod +x /usr/local/bin/loki
rm -f $${LOKI_ZIP_FILENAME}
echo "Loki binary installed at $(which loki)"
loki --version # Verify installation

# --- Create Loki User and Directories (Optional but Recommended) ---
# sudo groupadd --system loki || echo "Group 'loki' already exists."
# sudo useradd --system --no-create-home --gid loki loki || echo "User 'loki' already exists."
# Create directories needed by Loki components (config, runtime data, WAL, etc.)
# Using /data/loki as the base for runtime data.
# sudo mkdir -p /etc/loki /data/loki/wal /data/loki/chunks /data/loki/boltdb-shipper-active /data/loki/boltdb-shipper-cache /data/loki/boltdb-shipper-compactor /data/loki/rules
# sudo chown -R loki:loki /etc/loki /data/loki
# sudo chmod -R 750 /etc/loki /data/loki

# --- Create Loki Configuration ---
# Using root user and /tmp paths for simplicity. Use dedicated user and /data/loki for production.
sudo mkdir -p /etc/loki /tmp/loki/wal /tmp/loki/chunks /tmp/loki/boltdb-shipper-active /tmp/loki/boltdb-shipper-cache /tmp/loki/boltdb-shipper-compactor /tmp/loki/rules

echo "Creating Loki configuration file at /etc/loki/loki-config.yaml..."
cat <<EOF | sudo tee /etc/loki/loki-config.yaml
# Target 'all' runs Loki in monolithic mode (all components in one process).
# Suitable for single-instance setups or small clusters.
target: all

# WARNING: Authentication is disabled for simplicity. Enable for production.
auth_enabled: false

server:
  http_listen_port: 3100 # Port for Loki API (queries, writes)
  grpc_listen_port: 9096 # Port for internal gRPC communication (if needed)
  log_level: info        # Logging level for Loki server

# Common configuration shared across components.
common:
  instance_addr: 127.0.0.1 # Address used for identification in the ring (memberlist)
  path_prefix: /tmp/loki   # Base directory for local data storage (WAL, cache, etc.)
  storage:
    # Configure S3 as the primary object store.
    s3:
      bucketnames: $${LOKI_S3_BUCKET} # S3 bucket name from Terraform variable
      region: $${AWS_REGION}         # AWS region from Terraform variable
      # endpoint: s3.$${AWS_REGION}.amazonaws.com # Usually not needed, derived from region
      # insecure: false # Set to true if using non-HTTPS S3 endpoint (e.g., MinIO locally)
      # sse_encryption: false # Enable SSE (e.g., true for SSE-S3) for production
      # access_key_id/secret_access_key are automatically handled by the IAM role attached to the EC2 instance.
    # Configure the ring (for service discovery/coordination) using memberlist for single node.
    ring:
      kvstore:
        store: memberlist # Use memberlist for simple single-node or small cluster KV store
      # heartbeat_timeout: 1m # Default
      replication_factor: 1 # Only 1 instance, so replication factor is 1
  # Replication factor for the ingester ring (must match common.storage.ring.replication_factor).
  replication_factor: 1

# Schema configuration: Defines how logs are stored (index and chunks).
schema_config:
  configs:
    - from: 2024-01-01 # Date from which this schema config is active. Use a recent date.
      # Use BoltDB Shipper: Stores index locally, uploads to S3 periodically. Good balance.
      store: boltdb-shipper
      # Use S3 as the object store for chunks.
      object_store: s3
      # Schema version. v12 or v13 are recommended for recent Loki versions.
      schema: v13
      index:
        prefix: loki_index_ # Prefix for index files stored in S3.
        period: 24h         # How often index files are created (e.g., daily).

# Storage configuration details.
storage_config:
  # BoltDB Shipper configuration (for index files).
  boltdb_shipper:
    active_index_directory: /tmp/loki/boltdb-shipper-active # Local directory for the currently active index file.
    cache_location: /tmp/loki/boltdb-shipper-cache         # Local directory for caching downloaded index files.
    cache_ttl: 24h                                         # How long to cache index files locally (e.g., 24 hours).
    shared_store: s3                                       # Use S3 as the shared store for uploading index files.
  # Filesystem configuration (used only for WAL by ingesters).
  filesystem:
    directory: /tmp/loki/chunks # Directory for storing WAL chunks locally before they are flushed.

# Ingester configuration (handles incoming writes, builds chunks).
ingester:
  lifecycler:
    address: 127.0.0.1 # Address for ring identification.
    ring:
      kvstore:
        store: memberlist
      replication_factor: 1
    final_sleep: 0s # Time to wait before shutting down after leaving the ring. 0s for faster shutdowns in single node.
  # WAL (Write Ahead Log) configuration - crucial for preventing data loss on crashes.
  wal:
    enabled: true
    dir: /tmp/loki/wal # Directory to store WAL files. Must be on persistent local storage.
    # flush_on_shutdown: true # Default, ensures WAL is flushed on clean shutdown.
    # replay_memory_ceiling: 0 # Default, uses system memory based calculation.
  # How long chunks sit idle in memory before being flushed to storage.
  # Lower value means faster visibility but potentially more small chunks.
  chunk_idle_period: 5m # Default is 30m
  # How long chunks are retained in memory after flushing (0 deletes immediately).
  chunk_retain_period: 1m
  # Max age of a chunk in memory before forcing a flush.
  max_chunk_age: 1h # Default is 1h

# Querier configuration (handles read requests).
querier:
  # Max time range a query can look back. Adjust based on retention needs.
  max_look_back_period: 720h # 30 days

# Compactor configuration (merges index files in S3 for efficiency).
compactor:
  working_directory: /tmp/loki/boltdb-shipper-compactor # Local temp directory for compaction tasks.
  shared_store: s3                                     # Use S3 as the shared store for compacted blocks.
  compaction_interval: 10m                             # How often to check for compaction tasks.
  retention_enabled: false                             # Set to true to enable deleting old data based on retention period.
  # retention_delete_delay: 2h                         # Delay before deleting data marked for retention.
  # retention_delete_worker_count: 150                 # Number of workers for deletion.

# Ruler configuration (for recording and alerting rules). Optional.
ruler:
  enable_api: true # Expose ruler API endpoints.
  storage:
    type: local # Use local storage for rules in single-node setup.
    local:
      directory: /tmp/loki/rules
  # alertmanager_url: http://your-alertmanager-endpoint # URL of Alertmanager if used.
  ring:
    kvstore:
      store: memberlist # Use memberlist for ruler ring.

# Limits configuration (per-tenant limits, 'fake' tenant used when auth_enabled=false).
limits_config:
  # Allow sending labels starting with '_' (used by some clients like promtail's entry_parser).
  allow_unstructured_metadata: true
  # Max number of active streams per tenant.
  max_streams_per_user: 10000
  # Max number of label names per tenant.
  max_label_names_per_user: 5000
  # Reject logs older than this duration.
  reject_old_samples: true
  reject_old_samples_max_age: 168h # 7 days
  # Ingestion rate limits per tenant (adjust based on expected load).
  ingestion_rate_mb: 15      # MB per second
  ingestion_burst_size_mb: 30 # Burst allowed
EOF

# Validate the configuration file (optional)
echo "Validating Loki configuration..."
sudo /usr/local/bin/loki -config.file=/etc/loki/loki-config.yaml -validate-config || echo "Loki config validation failed (continuing...)"


# --- Create systemd Service File ---
echo "Creating systemd service file for Loki at /etc/systemd/system/loki.service..."
cat <<EOF | sudo tee /etc/systemd/system/loki.service
[Unit]
Description=Grafana Loki Logging System
Documentation=https://grafana.com/docs/loki/latest/
Wants=network-online.target
After=network-online.target

[Service]
# User=loki # Use dedicated user if created
# Group=loki # Use dedicated group if created
User=root # Running as root for simplicity
Group=root # Running as root for simplicity
WorkingDirectory=/etc/loki

# Run Loki with the specified config file and target 'all' for monolithic mode.
ExecStart=/usr/local/bin/loki -config.file=/etc/loki/loki-config.yaml -target=all
Restart=on-failure # Restart if the service fails
RestartSec=5s

# Optional: Redirect stdout/stderr to syslog
# StandardOutput=syslog
# StandardError=syslog
# SyslogIdentifier=loki

# Optional: Resource limits
# LimitNOFILE=1048576
# LimitNPROC=8192

[Install]
WantedBy=multi-user.target
EOF

# --- Enable and Start Loki Service ---
echo "Reloading systemd daemon, enabling and starting Loki service..."
sudo systemctl daemon-reload
sudo systemctl enable loki.service
sudo systemctl start loki.service
sudo systemctl status loki.service --no-pager # Check status

echo "--- Loki User Data Script Finished ---"
echo "Timestamp: $(date)"
