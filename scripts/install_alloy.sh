#!/bin/bash
# User data script for Grafana Alloy instance
# This script is executed by cloud-init when the EC2 instance launches.
# It installs and configures Grafana Alloy.

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Variables passed from Terraform ---
# These variables are substituted by the Terraform 'templatefile' function.
ALLOY_VERSION="${alloy_version}"
ALLOY_ZIP_FILENAME="${alloy_zip_filename}"
ALLOY_BINARY_NAME="${alloy_binary_name}"
LOKI_PRIVATE_IP="${loki_private_ip}"
MIMIR_PRIVATE_IP="${mimir_private_ip}"

# --- Logging ---
# Redirect stdout and stderr to cloud-init output log for easier debugging
exec > >(tee /var/log/cloud-init-output.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "--- Starting Alloy User Data Script ---"
echo "Timestamp: $(date)"
echo "Alloy Version to install: $$ALLOY_VERSION"
echo "Loki Private IP (Target): $$LOKI_PRIVATE_IP"
echo "Mimir Private IP (Target): $$MIMIR_PRIVATE_IP"

# --- System Update and Dependencies ---
echo "Updating system packages and installing dependencies..."
sudo dnf update -y
# wget and unzip are needed for downloading and extracting Alloy. tar/gzip might be needed for other tools.
sudo dnf install -y wget unzip tar gzip

# --- Download and Install Alloy ---
echo "Downloading Grafana Alloy version $$ALLOY_VERSION..."
cd /tmp # Work in the /tmp directory
wget --quiet "https://github.com/grafana/alloy/releases/download/$${ALLOY_VERSION}/$${ALLOY_ZIP_FILENAME}" -O $${ALLOY_ZIP_FILENAME}

echo "Installing Alloy..."
unzip -o $${ALLOY_ZIP_FILENAME} # -o overwrites existing files without prompting
sudo mv ./$${ALLOY_BINARY_NAME} /usr/local/bin/alloy # Move the binary to a standard location
sudo chmod +x /usr/local/bin/alloy # Make the binary executable
rm -f $${ALLOY_ZIP_FILENAME} # Clean up the downloaded zip file
echo "Alloy binary installed at $(which alloy)"
alloy --version # Verify installation

# --- Create Alloy User and Directories (Optional but Recommended) ---
# Running as a dedicated user improves security.
# sudo groupadd --system alloy || echo "Group 'alloy' already exists."
# sudo useradd --system --no-create-home --gid alloy alloy || echo "User 'alloy' already exists."
# sudo mkdir -p /etc/alloy /data/alloy
# sudo chown -R alloy:alloy /etc/alloy /data/alloy
# sudo chmod -R 750 /etc/alloy /data/alloy # Adjust permissions as needed

# --- Create Alloy Configuration ---
# Using root user and /tmp for data path for simplicity in this example.
# For production, use the dedicated user and /data/alloy.
sudo mkdir -p /etc/alloy /tmp/alloy-data # Create config and data directories

echo "Creating Alloy configuration file at /etc/alloy/config.alloy..."
# Use a HEREDOC to write the configuration file.
# Note the use of variables substituted by Terraform.
cat <<EOF | sudo tee /etc/alloy/config.alloy
// Basic logging configuration for Alloy itself.
logging {
  level  = "info"   // Log levels: debug, info, warn, error
  format = "logfmt" // Log format: logfmt, json
}

// OTLP receiver: Listens for telemetry data (logs, metrics, traces) from Faro.
otelcol.receiver.otlp "default" {
  // gRPC endpoint configuration.
  grpc {
    endpoint = "0.0.0.0:4317" // Listen on all interfaces, port 4317
    // transport = "tcp" // Default
    // Add TLS config here if needed
  }
  // HTTP endpoint configuration.
  http {
    endpoint = "0.0.0.0:4318" // Listen on all interfaces, port 4318
    // Add TLS config here if needed
    // cors: ... // Configure CORS if requests come directly from browsers outside the domain
  }

  // Define where the received data should be sent.
  output {
    logs    = [loki.write.default.input]            // Send logs to the loki.write component
    metrics = [prometheus.remote_write.mimir.receiver] // Send metrics to the prometheus.remote_write component
    // traces = [...] // Add trace exporter component here if needed (e.g., otelcol.exporter.otlp.tempo)
  }
}

// Loki write component: Sends logs to Loki.
loki.write "default" {
  // Define the Loki endpoint. Use the private IP provided by Terraform.
  endpoint {
    url = "http://$${LOKI_PRIVATE_IP}:3100/loki/api/v1/push" // Loki's push API endpoint
    // Add batching, retry, queue config if needed
  }
  // Optional: Add labels that will be attached to all logs sent by this component.
  external_labels = {
    source = "alloy", // Identify the source of the logs
    // cluster = "my-cluster", // Example additional label
  }
}

// Prometheus remote write component: Sends metrics to Mimir (or any Prometheus remote write compatible endpoint).
prometheus.remote_write "mimir" {
  // Define the Mimir remote write endpoint. Use the private IP provided by Terraform.
  endpoint {
    url = "http://$${MIMIR_PRIVATE_IP}:9009/api/v1/push" // Mimir's remote write endpoint
    // Add queue_config, metadata_config, http_client_config if needed
  }
}

// --- Example Trace Exporter (Uncomment and configure if sending traces) ---
// otelcol.exporter.otlp "tempo" {
//   client {
//     // Replace with your Tempo distributor endpoint (or other OTLP trace receiver)
//     endpoint = "tempo-distributor.tempo.svc.cluster.local:4317"
//     tls {
//       insecure = true // Set to 'false' and configure certs for production
//     }
//     // Add queueing, retry config if needed
//     // auth = ... // Add authentication if required
//   }
// }
EOF

# Validate the configuration file (optional step)
echo "Validating Alloy configuration..."
sudo /usr/local/bin/alloy fmt --check /etc/alloy/config.alloy || echo "Alloy config validation failed (continuing...)"

# --- Create systemd Service File ---
echo "Creating systemd service file for Alloy at /etc/systemd/system/alloy.service..."
cat <<EOF | sudo tee /etc/systemd/system/alloy.service
[Unit]
Description=Grafana Alloy observability collector
Documentation=https://grafana.com/docs/alloy/latest/
Wants=network-online.target # Wait for network to be ready
After=network-online.target

[Service]
# User=alloy # Use the dedicated user if created
# Group=alloy # Use the dedicated group if created
User=root # Running as root for simplicity
Group=root # Running as root for simplicity
WorkingDirectory=/etc/alloy

# Command to run Alloy. Use the data path created earlier.
# --server.http.listen-addr=127.0.0.1:12345 exposes Alloy's own UI/API only locally (optional)
ExecStart=/usr/local/bin/alloy run /etc/alloy/config.alloy --storage.path=/tmp/alloy-data --server.http.listen-addr=127.0.0.1:12345
Restart=on-failure # Restart the service if it fails
RestartSec=5s      # Wait 5 seconds before restarting

# Optional: Resource limits
# LimitNOFILE=1048576
# LimitNPROC=8192

[Install]
WantedBy=multi-user.target # Enable the service for standard multi-user runlevel
EOF

# --- Enable and Start Alloy Service ---
echo "Reloading systemd daemon, enabling and starting Alloy service..."
sudo systemctl daemon-reload          # Reload systemd manager configuration
sudo systemctl enable alloy.service   # Enable the service to start on boot
sudo systemctl start alloy.service    # Start the service immediately
sudo systemctl status alloy.service --no-pager # Check the status

echo "--- Alloy User Data Script Finished ---"
echo "Timestamp: $(date)"
