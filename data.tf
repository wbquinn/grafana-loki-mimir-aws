# --- Data Sources ---

# Get information about the availability zones in the configured AWS region.
data "aws_availability_zones" "available" {
  # Filter for zones that are currently available ('available' state).
  state = "available"
}

# Get information about the currently configured AWS region.
data "aws_region" "current" {}

# Find the latest Amazon Linux 2023 AMI for the x86_64 architecture.
data "aws_ami" "amazon_linux_2023" {
  most_recent = true            # Select the newest AMI matching the filters
  owners      = ["amazon"]      # Look for AMIs owned by Amazon

  # Filter criteria to identify the desired AMI:
  filter {
    name   = "name"
    # Pattern matching the Amazon Linux 2023 naming convention.
    # Example: al2023-ami-2023.20240415.0-kernel-6.1-x86_64
    values = ["al2023-ami-2023.*-kernel-*-x86_64"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]         # Specify the desired CPU architecture
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]            # Hardware Virtual Machine (standard for modern instances)
  }
  filter {
    name   = "root-device-type"
    values = ["ebs"]            # Instances using Elastic Block Store for the root volume
  }
}

# Construct the IAM policy document required for EC2 instances (Loki/Mimir) to access S3.
# This makes the policy definition cleaner and reusable.
data "aws_iam_policy_document" "grafana_s3_policy_doc" {
  statement {
    sid = "ListBuckets" # Statement ID for clarity
    actions = [
      "s3:ListBucket"   # Allows listing objects within the specified buckets
    ]
    resources = [
      # ARN references to the S3 buckets created in main.tf
      aws_s3_bucket.loki_storage.arn,
      aws_s3_bucket.mimir_storage.arn,
    ]
    # Optional condition: Restrict listing to specific prefixes if needed
    # condition {
    #   test     = "StringLike"
    #   variable = "s3:prefix"
    #   values   = ["loki_index_/*", "mimir_blocks/*"]
    # }
  }
  statement {
    sid = "ManageObjectsInBuckets" # Statement ID for clarity
    actions = [
      "s3:PutObject",     # Allows writing objects (log chunks, metric blocks)
      "s3:GetObject",     # Allows reading objects
      "s3:DeleteObject"   # Allows deleting objects (needed for compaction, retention)
    ]
    resources = [
      # Allows actions on any object within the specified buckets
      "${aws_s3_bucket.loki_storage.arn}/*",
      "${aws_s3_bucket.mimir_storage.arn}/*",
    ]
  }
}
