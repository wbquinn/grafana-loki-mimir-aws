# --- SSH Key Generation ---

# Generate a 4096-bit RSA private key using the TLS provider.
resource "tls_private_key" "deployer_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Create an EC2 Key Pair resource in AWS using the public key derived from the generated private key.
resource "aws_key_pair" "generated_key" {
  key_name   = local.ssh_key_name # Use the constructed key name from locals.tf
  public_key = tls_private_key.deployer_key.public_key_openssh # Provide the public key in OpenSSH format
  tags       = local.common_tags # Apply common tags
}

# Save the generated private key to a local file using the Local provider.
resource "local_file" "private_key_pem" {
  content         = tls_private_key.deployer_key.private_key_pem # Content is the private key in PEM format
  filename        = var.private_key_filename                   # Use the filename defined in variables.tf
  file_permission = "0600" # Set file permissions to read/write only for the owner (security best practice)
  # WARNING: Ensure this file is added to your .gitignore and handled securely!
}

# --- Networking ---

# Create a Virtual Private Cloud (VPC) for the Grafana stack.
resource "aws_vpc" "grafana_vpc" {
  cidr_block           = "10.0.0.0/16"    # Define the IP address range for the VPC
  enable_dns_support   = true             # Enable DNS resolution within the VPC
  enable_dns_hostnames = true             # Enable DNS hostnames for instances within the VPC
  tags                 = merge(local.common_tags, { Name = "${var.project_tag_value}-vpc" }) # Apply common tags and a specific Name tag
}

# Create a public subnet within the VPC.
resource "aws_subnet" "grafana_subnet" {
  vpc_id                  = aws_vpc.grafana_vpc.id                # Associate with the created VPC
  cidr_block              = "10.0.1.0/24"                         # Define the IP address range for the subnet
  availability_zone       = data.aws_availability_zones.available.names[0] # Place the subnet in the first available AZ in the region
  map_public_ip_on_launch = true                                  # Automatically assign public IPs to instances launched in this subnet (for easy access in this simple setup)
  tags                    = merge(local.common_tags, { Name = "${var.project_tag_value}-subnet" }) # Apply tags
}

# Create an Internet Gateway (IGW) to allow communication between the VPC and the internet.
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.grafana_vpc.id # Attach to the created VPC
  tags   = merge(local.common_tags, { Name = "${var.project_tag_value}-igw" }) # Apply tags
}

# Create a route table for the public subnet.
resource "aws_route_table" "rt" {
  vpc_id = aws_vpc.grafana_vpc.id # Associate with the created VPC

  # Route traffic destined for the internet (0.0.0.0/0) through the Internet Gateway.
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  tags = merge(local.common_tags, { Name = "${var.project_tag_value}-rt" }) # Apply tags
}

# Associate the route table with the public subnet.
resource "aws_route_table_association" "rta" {
  subnet_id      = aws_subnet.grafana_subnet.id
  route_table_id = aws_route_table.rt.id
}

# --- Security Groups ---

# Security group to allow SSH access.
resource "aws_security_group" "ssh_access" {
  name        = "${var.project_tag_value}-ssh-access-sg"
  description = "Allow SSH access from specified CIDRs"
  vpc_id      = aws_vpc.grafana_vpc.id

  # Ingress rule: Allow TCP traffic on port 22 (SSH) from the allowed CIDR blocks.
  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidr # Use the variable for allowed IPs
  }
  # Egress rule: Allow all outbound traffic.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # -1 means all protocols
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(local.common_tags, { Name = "${var.project_tag_value}-ssh-sg" }) # Apply tags
}

# Security group for the Alloy instance.
resource "aws_security_group" "alloy" {
  name        = "${var.project_tag_value}-alloy-sg"
  description = "Allow OTLP traffic to Alloy from specified CIDRs and internal traffic"
  vpc_id      = aws_vpc.grafana_vpc.id

  # Ingress rule: Allow OTLP/gRPC traffic (port 4317) from allowed Faro CIDRs.
  ingress {
    description = "OTLP/gRPC from Faro"
    from_port   = 4317
    to_port     = 4317
    protocol    = "tcp"
    cidr_blocks = var.allowed_faro_cidr # Use the variable for allowed IPs
  }
  # Ingress rule: Allow OTLP/HTTP traffic (port 4318) from allowed Faro CIDRs.
  ingress {
    description = "OTLP/HTTP from Faro"
    from_port   = 4318
    to_port     = 4318
    protocol    = "tcp"
    cidr_blocks = var.allowed_faro_cidr # Use the variable for allowed IPs
  }
  # Egress rule: Allow all outbound traffic (to Loki, Mimir, internet for downloads).
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(local.common_tags, { Name = "${var.project_tag_value}-alloy-sg" }) # Apply tags
}

# Security group for the Loki instance.
resource "aws_security_group" "loki" {
  name        = "${var.project_tag_value}-loki-sg"
  description = "Allow traffic to Loki API from Alloy and potentially Grafana"
  vpc_id      = aws_vpc.grafana_vpc.id

  # Ingress rule: Allow traffic from the Alloy security group to Loki's API port (3100).
  ingress {
    description     = "Loki API from Alloy"
    from_port       = 3100
    to_port         = 3100
    protocol        = "tcp"
    security_groups = [aws_security_group.alloy.id] # Allow traffic only from instances in the Alloy SG
  }
  # TODO: Add ingress rule here if Grafana is deployed separately and needs to query Loki.
  # ingress {
  #   description     = "Loki API from Grafana"
  #   from_port       = 3100
  #   to_port         = 3100
  #   protocol        = "tcp"
  #   security_groups = [aws_security_group.grafana.id] # Replace with your Grafana SG ID
  # }

  # Egress rule: Allow all outbound traffic (to S3, internet for downloads).
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(local.common_tags, { Name = "${var.project_tag_value}-loki-sg" }) # Apply tags
}

# Security group for the Mimir instance.
resource "aws_security_group" "mimir" {
  name        = "${var.project_tag_value}-mimir-sg"
  description = "Allow traffic to Mimir API from Alloy and potentially Grafana"
  vpc_id      = aws_vpc.grafana_vpc.id

  # Ingress rule: Allow traffic from the Alloy security group to Mimir's API port (9009).
  ingress {
    description     = "Mimir Push API from Alloy"
    from_port       = 9009 # Default Mimir HTTP/API port
    to_port         = 9009
    protocol        = "tcp"
    security_groups = [aws_security_group.alloy.id] # Allow traffic only from instances in the Alloy SG
  }
  # TODO: Add ingress rule here if Grafana is deployed separately and needs to query Mimir.
  # ingress {
  #   description     = "Mimir API from Grafana"
  #   from_port       = 9009
  #   to_port         = 9009
  #   protocol        = "tcp"
  #   security_groups = [aws_security_group.grafana.id] # Replace with your Grafana SG ID
  # }

  # Egress rule: Allow all outbound traffic (to S3, internet for downloads).
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(local.common_tags, { Name = "${var.project_tag_value}-mimir-sg" }) # Apply tags
}

# --- IAM ---

# Create an IAM role that EC2 instances can assume.
resource "aws_iam_role" "grafana_ec2_role" {
  # Construct a unique role name including the region
  name = "${var.project_tag_value}-ec2-s3-role-${data.aws_region.current.name}"
  # Define the trust policy allowing the EC2 service to assume this role.
  assume_role_policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [
      {
        Action    = "sts:AssumeRole",
        Effect    = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
  tags = local.common_tags # Apply common tags
}

# Create an IAM policy granting necessary S3 permissions based on the policy document.
resource "aws_iam_policy" "grafana_s3_policy" {
  # Construct a unique policy name including the region
  name        = "${var.project_tag_value}-loki-mimir-s3-policy-${data.aws_region.current.name}"
  description = "Policy granting S3 access for Loki and Mimir EC2 instances"
  policy      = data.aws_iam_policy_document.grafana_s3_policy_doc.json # Reference the policy document defined in data.tf
  tags        = local.common_tags # Apply common tags
}

# Attach the created S3 policy to the created EC2 role.
resource "aws_iam_role_policy_attachment" "attach_s3_policy" {
  role       = aws_iam_role.grafana_ec2_role.name
  policy_arn = aws_iam_policy.grafana_s3_policy.arn
}

# Create an EC2 instance profile, which acts as a container for the IAM role.
resource "aws_iam_instance_profile" "grafana_ec2_profile" {
  # Construct a unique instance profile name including the region
  name = "${var.project_tag_value}-ec2-s3-profile-${data.aws_region.current.name}"
  role = aws_iam_role.grafana_ec2_role.name # Associate the role with this profile
  tags = local.common_tags # Apply common tags
}

# --- Storage (S3 Buckets) ---

# Create the S3 bucket for Loki storage.
resource "aws_s3_bucket" "loki_storage" {
  bucket = var.loki_s3_bucket_name # Use the variable for the bucket name (must be globally unique)
  tags   = merge(local.common_tags, { Name = "${var.project_tag_value}-loki-storage" }) # Apply tags

  # Recommended for production: Enable versioning and server-side encryption.
  # versioning {
  #   enabled = true
  # }
  # server_side_encryption_configuration {
  #   rule {
  #     apply_server_side_encryption_by_default {
  #       sse_algorithm = "AES256"
  #     }
  #   }
  # }
  # lifecycle_rule { ... } # Add lifecycle rules for object expiration/transition
}

# Create the S3 bucket for Mimir storage.
resource "aws_s3_bucket" "mimir_storage" {
  bucket = var.mimir_s3_bucket_name # Use the variable for the bucket name (must be globally unique)
  tags   = merge(local.common_tags, { Name = "${var.project_tag_value}-mimir-storage" }) # Apply tags

  # Recommended for production: Enable versioning and server-side encryption.
  # versioning { ... }
  # server_side_encryption_configuration { ... }
  # lifecycle_rule { ... }
}

# --- Compute Instances ---

# Create the EC2 instance for Grafana Alloy.
resource "aws_instance" "alloy" {
  ami                    = data.aws_ami.amazon_linux_2023.id # Use the dynamically found latest AL2023 AMI ID
  instance_type          = var.alloy_instance_type          # Use the instance type variable
  subnet_id              = aws_subnet.grafana_subnet.id     # Launch in the created public subnet
  vpc_security_group_ids = [aws_security_group.ssh_access.id, aws_security_group.alloy.id] # Attach SSH and Alloy SGs
  key_name               = aws_key_pair.generated_key.key_name # Use the generated EC2 key pair
  iam_instance_profile   = aws_iam_instance_profile.grafana_ec2_profile.name # Attach the IAM profile (though Alloy doesn't directly use S3 here, Loki/Mimir do)

  # Use the templatefile function to render the user data script, passing variables.
  user_data = templatefile("${path.module}/scripts/install_alloy.sh", {
    # Variables expected by the install_alloy.sh script
    alloy_version    = var.alloy_version
    alloy_zip_filename = local.alloy_zip_filename
    alloy_binary_name= local.alloy_binary_name
    loki_private_ip  = aws_instance.loki.private_ip   # Pass Loki's private IP
    mimir_private_ip = aws_instance.mimir.private_ip  # Pass Mimir's private IP
  })

  # Apply common tags and a specific Name tag.
  tags = merge(local.common_tags, { Name = "${var.project_tag_value}-alloy-instance" })

  # Explicitly depend on the Loki and Mimir instances being created first,
  # as their private IPs are needed for the Alloy user data script.
  # Also depends on the key pair being created.
  depends_on = [aws_instance.loki, aws_instance.mimir, aws_key_pair.generated_key]
}

# Create the EC2 instance for Grafana Loki.
resource "aws_instance" "loki" {
  ami                    = data.aws_ami.amazon_linux_2023.id # Use dynamic AMI
  instance_type          = var.loki_instance_type           # Use variable
  subnet_id              = aws_subnet.grafana_subnet.id     # Launch in public subnet
  vpc_security_group_ids = [aws_security_group.ssh_access.id, aws_security_group.loki.id] # Attach SSH and Loki SGs
  key_name               = aws_key_pair.generated_key.key_name # Use generated key
  iam_instance_profile   = aws_iam_instance_profile.grafana_ec2_profile.name # Attach IAM profile for S3 access

  # Render the Loki user data script.
  user_data = templatefile("${path.module}/scripts/install_loki.sh", {
    # Variables expected by the install_loki.sh script
    loki_version       = var.loki_version
    loki_zip_filename  = local.loki_zip_filename
    loki_binary_name   = local.loki_binary_name
    loki_s3_bucket     = aws_s3_bucket.loki_storage.bucket # Pass the actual S3 bucket name
    aws_region         = var.aws_region                    # Pass the AWS region
  })

  # Apply tags.
  tags = merge(local.common_tags, { Name = "${var.project_tag_value}-loki-instance" })

  # Depends on the key pair being created.
  depends_on = [aws_key_pair.generated_key]
}

# Create the EC2 instance for Grafana Mimir.
resource "aws_instance" "mimir" {
  ami                    = data.aws_ami.amazon_linux_2023.id # Use dynamic AMI
  instance_type          = var.mimir_instance_type          # Use variable
  subnet_id              = aws_subnet.grafana_subnet.id     # Launch in public subnet
  vpc_security_group_ids = [aws_security_group.ssh_access.id, aws_security_group.mimir.id] # Attach SSH and Mimir SGs
  key_name               = aws_key_pair.generated_key.key_name # Use generated key
  iam_instance_profile   = aws_iam_instance_profile.grafana_ec2_profile.name # Attach IAM profile for S3 access

  # Render the Mimir user data script.
  user_data = templatefile("${path.module}/scripts/install_mimir.sh", {
    # Variables expected by the install_mimir.sh script
    mimir_version      = var.mimir_version
    mimir_zip_filename = local.mimir_zip_filename
    mimir_binary_name  = local.mimir_binary_name
    mimir_s3_bucket    = aws_s3_bucket.mimir_storage.bucket # Pass the actual S3 bucket name
    aws_region         = var.aws_region                     # Pass the AWS region
  })

  # Apply tags.
  tags = merge(local.common_tags, { Name = "${var.project_tag_value}-mimir-instance" })

  # Depends on the key pair being created.
  depends_on = [aws_key_pair.generated_key]
}
