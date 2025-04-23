
terraform {
  required_providers {
    # AWS Provider for managing AWS resources
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0" # Use a recent stable version
    }
    # TLS Provider for generating the SSH key pair
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    # Local Provider for saving the generated private key to a file
    local = {
      source = "hashicorp/local"
      version = "~> 2.4"
    }
  }
}

# Configure the AWS provider with the specified region
provider "aws" {
  region = var.aws_region
}
