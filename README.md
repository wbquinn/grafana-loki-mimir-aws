# grafana-loki-mimir-aws

Simple single-instance setup for grafana loki and mimir on aws

### Prerequisites

1. Install Terraform.

2. Configure your [AWS Credentials](https://registry.terraform.io/providers/hashicorp/aws/latest/docs#authentication-and-configuration) (e.g., using environment variables, shared credential file, or IAM role). Ensure the credentials have the permissions outlined in the "Terraform Execution IAM Policy" document.

3. Create a file named terraform.tfvars.You MUST define unique S3 bucket names in this file.
    - Define unique S3 bucket names.
    - Restrict allowed_ssh_cidr and allowed_grafana_cidr to your IP address/range.
    - Optionally override other variables.

   Example terraform.tfvars:

```
# REQUIRED: Replace with your globally unique bucket names
loki_s3_bucket_name  = "your-unique-loki-bucket-name-12345"
mimir_s3_bucket_name = "your-unique-mimir-bucket-name-67890"

# RECOMMENDED: Restrict access
allowed_ssh_cidr     = ["YOUR_PUBLIC_IP/32"] # Replace YOUR_PUBLIC_IP
allowed_grafana_cidr = ["YOUR_PUBLIC_IP/32"] # Replace YOUR_PUBLIC_IP

# Optional: Restrict Faro access if possible
# allowed_faro_cidr = ["YOUR_APP_SERVER_IP/32", "YOUR_CDN_IP_RANGE"]

# Optional: Override other defaults if needed
# grafana_version = "10.3.3"
# grafana_instance_type = "t3.small"

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

10. Access Grafana:

- Open the grafana_public_url in your browser.
- Log in with username admin and password admin.
  - You will be prompted to change the password.
- Configure Data Sources in Grafana:
  - Navigate to Configuration -> Data Sources.
  - Add Loki Data Source:
    - Select "Loki".
    - Name: Loki (or as desired)
    - URL: Use the loki_internal_endpoint output value (e.g., http://10.0.1.x:3100). Since Grafana is in the same VPC, it can reach Loki via its private IP.
      - Leave Auth settings as default (unless you enable auth in Loki later).
    - Click "Save & Test".
  - Add Prometheus Data Source (for Mimir):
    - Select "Prometheus".
    - Name: Mimir (or as desired)
    - URL: Use the mimir_internal_endpoint output value (e.g., http://10.0.1.y:9009).
      - Leave Auth settings as default.
    - Click "Save & Test".

### Removal
11. Cleanup: When you no longer need the resources, destroy them:`terraform destroy`
    Type yes when prompted. This will remove all AWS resources created by this configuration but will not delete the local private key file (.pem).
