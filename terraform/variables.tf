####################################################################
# NVIDIA SuperPod Lab — Root Variables
####################################################################

variable "aws_region" {
  description = "AWS region to deploy the SuperPod cluster into"
  type        = string
  default     = "eu-central-1"
}

variable "environment" {
  description = "Deployment environment label (e.g. lab, dev, prod) — applied to all resource tags"
  type        = string
  default     = "lab"
}

variable "instance_type" {
  description = "EC2 instance type for the GPU node (must be a GPU-enabled type such as g4dn, p3, p4d)"
  type        = string
  default     = "g4dn.xlarge"
}

variable "use_spot_instance" {
  description = "Launch the GPU node as a Spot instance to reduce cost; set false for On-Demand"
  type        = bool
  default     = true
}

variable "spot_max_price" {
  description = "Maximum hourly Spot price in USD; instance is terminated if market price exceeds this"
  type        = string
  default     = "0.20"
}

variable "ssh_public_key" {
  description = "RSA/Ed25519 public key content to inject into the GPU node for SSH access"
  type        = string
  sensitive   = true
}

variable "allowed_ssh_cidrs" {
  description = "List of CIDR blocks permitted to reach the GPU node (SSH, monitoring ports). Restrict to your IP in production."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "root_volume_size_gb" {
  description = "Size in GiB of the root EBS volume (gp3); should be large enough for OS, drivers, and Docker images"
  type        = number
  default     = 100
}

variable "data_volume_size_gb" {
  description = "Size in GiB of the secondary EBS data volume (gp3) mounted at /mnt/data; set 0 to disable"
  type        = number
  default     = 200
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
