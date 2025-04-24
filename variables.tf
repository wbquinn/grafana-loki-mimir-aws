# --- General Variables ---

variable "aws_region" {
  description = "AWS region to deploy resources."
  type        = string
  default     = "eu-west-1" # Defaulting to eu-west-1 as requested
}

variable "project_tag_value" {
  description = "Value for the 'project' tag applied to all resources."
  type        = string
  default     = "ak-grafana-wbq" # Defaulting to the requested project tag value
}

# --- Networking Variables ---

variable "allowed_ssh_cidr" {
  description = "List of CIDR blocks allowed for SSH access to the EC2 instances."
  type        = list(string)
  default     = ["0.0.0.0/0"] # WARNING: For security, restrict this to your specific IP address range.
  validation {
    condition     = alltrue([for cidr in var.allowed_ssh_cidr : can(cidrhost(cidr, 0))])
    error_message = "Each item in allowed_ssh_cidr must be a valid CIDR block (e.g., \"1.2.3.4/32\")."
  }
}

variable "allowed_faro_cidr" {
  description = "List of CIDR blocks allowed to send OTLP data to the Alloy instance."
  type        = list(string)
  default     = ["0.0.0.0/0"] # WARNING: For security, restrict this to your application server/CDN IP ranges.
  validation {
    condition     = alltrue([for cidr in var.allowed_faro_cidr : can(cidrhost(cidr, 0))])
    error_message = "Each item in allowed_faro_cidr must be a valid CIDR block."
  }
}

variable "allowed_grafana_cidr" {
  description = "List of CIDR blocks allowed access to the Grafana UI (port 3000)."
  type        = list(string)
  default     = ["0.0.0.0/0"] # WARNING: For security, restrict this to your specific IP address range.
  validation {
    condition     = alltrue([for cidr in var.allowed_grafana_cidr : can(cidrhost(cidr, 0))])
    error_message = "Each item in allowed_grafana_cidr must be a valid CIDR block."
  }
}

# --- Storage Variables ---

variable "loki_s3_bucket_name" {
  description = "Globally unique name for the Loki S3 storage bucket. MUST be provided."
  type        = string
  default = "epos-graf-loki"
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.loki_s3_bucket_name)) && !can(regex("(\\d{1,3}\\.){3}\\d{1,3}", var.loki_s3_bucket_name))
    error_message = "Loki S3 bucket name must be globally unique, 3-63 characters long, contain only lowercase letters, numbers, dots (.), and hyphens (-), start/end with a letter or number, and not be formatted as an IP address."
  }
}

variable "mimir_s3_bucket_name" {
  description = "Globally unique name for the Mimir S3 storage bucket. MUST be provided."
  type        = string
  default = "epos-graf-mimir"
   validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.mimir_s3_bucket_name)) && !can(regex("(\\d{1,3}\\.){3}\\d{1,3}", var.mimir_s3_bucket_name))
    error_message = "Mimir S3 bucket name must be globally unique, 3-63 characters long, contain only lowercase letters, numbers, dots (.), and hyphens (-), start/end with a letter or number, and not be formatted as an IP address."
  }
}

# --- Compute Variables ---

variable "alloy_instance_type" {
  description = "EC2 instance type for the Grafana Alloy instance."
  type        = string
  default     = "t3.small"
}

variable "loki_instance_type" {
  description = "EC2 instance type for the Grafana Loki instance."
  type        = string
  default     = "t3.small" # Consider t3.large or m-series for production Loki
}

variable "mimir_instance_type" {
  description = "EC2 instance type for the Grafana Mimir instance."
  type        = string
  default     = "t3.small" # Mimir often benefits from more memory/CPU
}

variable "grafana_instance_type" {
  description = "EC2 instance type for the Grafana server instance."
  type        = string
  default     = "t3.small" # t3.small might be sufficient for light use
}

variable "ssh_key_name_prefix" {
  description = "Prefix for the name of the generated EC2 Key Pair in AWS."
  type        = string
  default     = "grafana-stack-deployer-key"
}

variable "private_key_filename" {
  description = "Local filename where the generated private SSH key will be saved."
  type        = string
  default     = "grafana_stack_key.pem" # Ensure this is added to .gitignore
}

# --- Software Version Variables ---

variable "alloy_version" {
  description = "Grafana Alloy version tag to install (e.g., 'v1.1.0'). Check GitHub releases."
  type        = string
  default     = "v1.8.2" # Update to the desired latest stable version
}

variable "loki_version" {
  description = "Grafana Loki version tag to install (e.g., 'v3.0.0'). Check GitHub releases."
  type        = string
  default     = "v3.5.0" # Update to the desired latest stable version
}

variable "mimir_version" {
  description = "Grafana Mimir version tag to install (e.g., 'mimir-2.11.1'). Check GitHub releases."
  type        = string
  default     = "mimir-2.16.0" # Update to the desired latest stable version
}

variable "grafana_version" {
  description = "Grafana OSS version to install (e.g., '10.4.2'). Use 'latest' for the newest release. Check Grafana website for versions."
  type        = string
  default     = "11.6.1" # Specify a version or use 'latest'
}
