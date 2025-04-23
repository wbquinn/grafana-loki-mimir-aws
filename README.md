# grafana-loki-mimir-aws

Simple single-instance setup for grafana loki and mimir on aws

### Prerequisites

1. Install Terraform.

2. Configure your AWS Credentials (e.g., using environment variables, shared credential file, or IAM role). Ensure the credentials have the permissions outlined in the "Terraform Execution IAM Policy" document.

3. Create a file named terraform.tfvars.You MUST define unique S3 bucket names in this file.Optionally override other variables like allowed_ssh_cidr.

   Example terraform.tfvars:

```
# REQUIRED: Replace with your globally unique bucket names
loki_s3_bucket_name  = "your-unique-loki-bucket-name-12345"
mimir_s3_bucket_name = "your-unique-mimir-bucket-name-67890"

# RECOMMENDED: Restrict SSH access to your IP
allowed_ssh_cidr = ["YOUR_PUBLIC_IP/32"] # Replace YOUR_PUBLIC_IP

# Optional: Restrict Faro access if possible
# allowed_faro_cidr = ["YOUR_APP_SERVER_IP/32", "YOUR_CDN_IP_RANGE"]

# Optional: Override other defaults if needed
# aws_region = "eu-central-1"
# alloy_instance_type = "t3.large"
```

### Use Terraform
1. Initialize Terraform: Open your terminal in the project directory and run:`terraform init`

5. Plan Deployment: Review the resources Terraform will create:`terraform plan -out=tfplan`

6. Apply Deployment: Create the resources in AWS:`terraform apply tfplan`
   Type yes when prompted to confirm.

7. Access Outputs: Terraform will display the outputs (IP addresses, bucket names, key filename, SSH commands).

8. Use the Private Key: The generated private key (e.g., grafana_stack_key.pem) will be saved in your project directory. Use it for SSH access:

```
chmod 400 grafana_stack_key.pem # Set correct permissions first
ssh -i grafana_stack_key.pem ec2-user@<INSTANCE_PUBLIC_IP>
```

    (Replace <INSTANCE_PUBLIC_IP> with the IP from the outputs).

9. Configure Faro: Use the `alloy_otlp_http_endpoint_base` or `alloy_otlp_grpc_endpoint` output to configure your Grafana Faro agent in your web application.

10. Configure Grafana Data Sources: If you have a separate Grafana instance (within the same VPC or peered), use the `loki_internal_endpoint` and `mimir_internal_endpoint outputs` to configure Loki and Prometheus data sources respectively. You might need to adjust security groups to allow traffic from your Grafana instance to Loki/Mimir.

### Removal
11. Cleanup: When you no longer need the resources, destroy them:`terraform destroy`
    Type yes when prompted. This will remove all AWS resources created by this configuration but will not delete the local private key file (.pem).
