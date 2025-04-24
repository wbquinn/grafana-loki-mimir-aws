# --- Outputs ---

output "generated_private_key_filename" {
  description = "Filename of the generated private SSH key saved locally. WARNING: Secure this file and add to .gitignore!"
  value       = local_file.private_key_pem.filename
}

output "ssh_command_alloy" {
  description = "Example SSH command to connect to the Alloy instance using the generated key."
  value       = "ssh -i ${local_file.private_key_pem.filename} ec2-user@${aws_instance.alloy.public_ip}"
  sensitive   = true
}

output "ssh_command_loki" {
  description = "Example SSH command to connect to the Loki instance using the generated key."
  value       = "ssh -i ${local_file.private_key_pem.filename} ec2-user@${aws_instance.loki.public_ip}"
  sensitive   = true
}

output "ssh_command_mimir" {
  description = "Example SSH command to connect to the Mimir instance using the generated key."
  value       = "ssh -i ${local_file.private_key_pem.filename} ec2-user@${aws_instance.mimir.public_ip}"
  sensitive   = true
}

output "ssh_command_grafana" {
  description = "Example SSH command to connect to the Grafana instance using the generated key."
  value       = "ssh -i ${local_file.private_key_pem.filename} ec2-user@${aws_instance.grafana.public_ip}"
  sensitive   = true
}

output "alloy_public_ip" {
  description = "Public IP address of the Grafana Alloy instance. Use this for Faro configuration."
  value       = aws_instance.alloy.public_ip
}

output "alloy_otlp_grpc_endpoint" {
  description = "Alloy OTLP gRPC endpoint URL for Faro (use with gRPC transport config in Faro)."
  value       = "http://${aws_instance.alloy.public_ip}:4317"
}

output "alloy_otlp_http_endpoint_base" {
  description = "Base Alloy OTLP HTTP endpoint URL for Faro. Append '/v1/logs', '/v1/traces', or '/v1/metrics' as needed."
  value       = "http://${aws_instance.alloy.public_ip}:4318"
}

output "grafana_public_url" {
  description = "URL to access the Grafana UI. Default login: admin / admin (change on first login)."
  value       = "http://${aws_instance.grafana.public_ip}:3000"
}

output "loki_internal_endpoint" {
  description = "Internal HTTP endpoint for Loki (use this URL for the Loki data source in Grafana)."
  value       = "http://${aws_instance.loki.private_ip}:3100"
}

output "mimir_internal_endpoint" {
  description = "Internal HTTP endpoint for Mimir (use this URL for the Prometheus data source pointing to Mimir in Grafana)."
  value       = "http://${aws_instance.mimir.private_ip}:9009"
}

output "loki_s3_bucket_name" {
  description = "Name of the S3 bucket created for Loki storage."
  value       = aws_s3_bucket.loki_storage.bucket
}

output "mimir_s3_bucket_name" {
  description = "Name of the S3 bucket created for Mimir storage."
  value       = aws_s3_bucket.mimir_storage.bucket
}

output "latest_al2023_ami_id_used" {
  description = "The specific ID of the Amazon Linux 2023 AMI that was automatically selected and used for the instances."
  value       = data.aws_ami.amazon_linux_2023.id
}

output "ssh_key_pair_name_in_aws" {
  description = "The name of the EC2 Key Pair resource created in AWS."
  value       = aws_key_pair.generated_key.key_name
}
