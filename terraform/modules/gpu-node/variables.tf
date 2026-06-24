# Copyright 2026 Hitesh Kumar Sahu — https://hiteshsahu.com
# SPDX-License-Identifier: Apache-2.0

####################################################################
# NVIDIA SuperPod — GPU Node Module Variables
####################################################################

variable "name" {
  description = "Unique name prefix applied to all resources created by this module"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC in which to launch the GPU node"
  type        = string
}

variable "subnet_id" {
  description = "ID of the subnet to place the GPU node in"
  type        = string
}

variable "availability_zone" {
  description = "Availability zone for the GPU node and its EBS data volume (must match the subnet)"
  type        = string
}

variable "allowed_cidrs" {
  description = "CIDR blocks allowed inbound access to SSH and monitoring ports; restrict to known IPs in production"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "instance_type" {
  description = "EC2 instance type for the GPU node (must be a GPU-enabled type such as g4dn, p3, p4d)"
  type        = string
  default     = "g4dn.xlarge"
}

variable "ami_id" {
  description = "Custom AMI ID to use for the GPU node; leave empty to use the latest Ubuntu 22.04 LTS AMI"
  type        = string
  default     = ""
}

variable "use_spot_instance" {
  description = "Launch the GPU node as a Spot instance to reduce cost; set false for On-Demand"
  type        = bool
  default     = true
}

variable "spot_max_price" {
  description = "Maximum hourly Spot price in USD; instance is terminated if the market price exceeds this"
  type        = string
  default     = "0.20"
}

variable "ssh_public_key" {
  description = "RSA/Ed25519 public key content to inject into the node for SSH access; leave empty to skip key pair creation"
  type        = string
  sensitive   = true
  default     = ""
}

variable "root_volume_size_gb" {
  description = "Size in GiB of the root EBS volume (gp3); should accommodate OS, drivers, Docker images, and model checkpoints"
  type        = number
  default     = 100
}

variable "data_volume_size_gb" {
  description = "Size in GiB of the secondary EBS data volume (gp3) mounted at /mnt/data; set 0 to disable"
  type        = number
  default     = 200
}

variable "assign_elastic_ip" {
  description = "Assign an Elastic IP to the GPU node so the public IP is stable across stop/start cycles"
  type        = bool
  default     = true
}

variable "enable_placement_group" {
  description = "Place the GPU node in a cluster placement group for low-latency GPU-to-GPU networking (requires compatible instance type)"
  type        = bool
  default     = false
}

variable "nvidia_driver_version" {
  description = "NVIDIA driver major version to install via apt (e.g. 535, 550)"
  type        = string
  default     = "535"
}

variable "cuda_version" {
  description = "CUDA Toolkit version to install via apt, formatted as <major>-<minor> (e.g. 12-3)"
  type        = string
  default     = "12-3"
}

variable "kubernetes_version" {
  description = "Kubernetes minor version used to pin the kubectl apt repository (e.g. 1.29)"
  type        = string
  default     = "1.29"
}

variable "enable_dcgm_exporter" {
  description = "Install NVIDIA DCGM and enable the datacenter-gpu-manager service for GPU telemetry"
  type        = bool
  default     = true
}

variable "data_bucket_name" {
  description = "S3 bucket name the GPU node IAM role is granted read/write access to for training data and checkpoints"
  type        = string
  default     = "superpod-data"
}

variable "tags" {
  description = "Map of additional tags to merge onto all resources created by this module"
  type        = map(string)
  default     = {}
}
