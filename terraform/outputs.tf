####################################################################
# NVIDIA SuperPod Lab — Root Outputs
####################################################################

output "vpc_id" {
  description = "ID of the VPC created for the SuperPod cluster"
  value       = module.vpc.vpc_id
}

output "gpu_node_public_ip" {
  description = "Elastic IP address of the GPU node"
  value       = module.gpu_node_01.public_ip
}

output "gpu_node_instance_id" {
  description = "EC2 instance ID of the GPU node"
  value       = module.gpu_node_01.instance_id
}

output "ssh_command" {
  description = "SSH command to connect to the GPU node"
  value       = "ssh -i ~/.ssh/id_rsa ubuntu@${module.gpu_node_01.public_ip}"
}

output "grafana_url" {
  description = "Grafana dashboard URL (available after observability stack is deployed)"
  value       = "http://${module.gpu_node_01.public_ip}:3000"
}

output "prometheus_url" {
  description = "Prometheus metrics URL"
  value       = "http://${module.gpu_node_01.public_ip}:9090"
}

output "dcgm_metrics_url" {
  description = "DCGM Exporter raw GPU metrics endpoint"
  value       = "http://${module.gpu_node_01.public_ip}:9400/metrics"
}

output "instance_type" {
  description = "EC2 instance type provisioned for the GPU node"
  value       = module.gpu_node_01.instance_type
}

output "ami_id" {
  description = "AMI ID used to launch the GPU node"
  value       = module.gpu_node_01.ami_id
}

output "availability_zone" {
  description = "Availability zone the GPU node was provisioned in"
  value       = module.gpu_node_01.availability_zone
}

output "validate_gpu_command" {
  description = "Quick command to validate GPU is available after SSH"
  value       = "nvidia-smi && nvcc --version && ./scripts/validate-gpu.sh"
}
