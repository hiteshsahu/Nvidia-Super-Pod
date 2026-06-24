# Copyright 2026 Hitesh Kumar Sahu — https://hiteshsahu.com
# SPDX-License-Identifier: Apache-2.0

####################################################################
# NVIDIA SuperPod — GPU Node Module Outputs
####################################################################

output "instance_id" {
  description = "EC2 instance ID of the GPU node"
  value       = aws_instance.gpu_node.id
}

output "instance_type" {
  description = "EC2 instance type of the GPU node"
  value       = aws_instance.gpu_node.instance_type
}

output "ami_id" {
  description = "AMI ID used to launch the GPU node"
  value       = aws_instance.gpu_node.ami
}

output "availability_zone" {
  description = "Availability zone the GPU node is running in"
  value       = aws_instance.gpu_node.availability_zone
}

output "private_ip" {
  description = "Private IP address of the GPU node"
  value       = aws_instance.gpu_node.private_ip
}

output "public_ip" {
  description = "Public IP address of the GPU node (Elastic IP if assigned, otherwise ephemeral)"
  value       = var.assign_elastic_ip ? aws_eip.this[0].public_ip : aws_instance.gpu_node.public_ip
}

output "security_group_id" {
  description = "Security group ID attached to the GPU node"
  value       = aws_security_group.gpu_node.id
}

output "iam_role_arn" {
  description = "ARN of the IAM role attached to the GPU node"
  value       = aws_iam_role.gpu_node.arn
}

output "data_volume_id" {
  description = "EBS data volume ID (null if data volume is disabled)"
  value       = var.data_volume_size_gb > 0 ? aws_ebs_volume.data[0].id : null
}

output "ssh_command" {
  description = "SSH command to connect to the GPU node"
  value       = "ssh -i ~/.ssh/id_rsa ubuntu@${var.assign_elastic_ip ? aws_eip.this[0].public_ip : aws_instance.gpu_node.public_ip}"
}

output "grafana_url" {
  description = "Grafana dashboard URL"
  value       = "http://${var.assign_elastic_ip ? aws_eip.this[0].public_ip : aws_instance.gpu_node.public_ip}:3000"
}

output "prometheus_url" {
  description = "Prometheus metrics URL"
  value       = "http://${var.assign_elastic_ip ? aws_eip.this[0].public_ip : aws_instance.gpu_node.public_ip}:9090"
}

output "dcgm_metrics_url" {
  description = "DCGM Exporter raw GPU metrics endpoint"
  value       = "http://${var.assign_elastic_ip ? aws_eip.this[0].public_ip : aws_instance.gpu_node.public_ip}:9400/metrics"
}
