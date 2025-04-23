# --- Local Values ---

locals {
  # Define common tags to be applied consistently across resources.
  common_tags = {
    project    = var.project_tag_value # Use the variable for project tagging
    managed-by = "terraform"           # Indicate resource management method
    stack      = "grafana-loki-mimir"   # Identify the stack components belong to
  }

  # Construct download filenames based on version conventions.
  # Assumes standard naming convention used by Grafana projects.
  mimir_zip_filename = "mimir-linux-amd64.zip"
  mimir_binary_name  = "mimir-linux-amd64" # The name of the binary inside the zip

  loki_zip_filename = "loki-linux-amd64.zip"
  loki_binary_name  = "loki-linux-amd64" # The name of the binary inside the zip

  alloy_zip_filename = "alloy-linux-amd64.zip"
  alloy_binary_name  = "alloy-linux-amd64" # The name of the binary inside the zip

  # Construct the full EC2 key pair name using the prefix and current region.
  # This helps ensure uniqueness if deploying in multiple regions.
  ssh_key_name = "${var.ssh_key_name_prefix}-${data.aws_region.current.name}"
}
