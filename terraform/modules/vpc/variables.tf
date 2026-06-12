####################################################################
# NVIDIA SuperPod — VPC Module Variables
####################################################################

variable "name" {
  description = "Name prefix applied to all VPC resources (VPC, subnets, gateways, route tables)"
  type        = string
  default     = "superpod"
}

variable "vpc_cidr" {
  description = "IPv4 CIDR block for the VPC (e.g. 10.0.0.0/16)"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "List of CIDR blocks for public subnets; one subnet is created per entry, each in its own AZ"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "List of CIDR blocks for private subnets; one subnet is created per entry, each in its own AZ"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "availability_zones" {
  description = "Ordered list of AZs to distribute subnets across; length must match public and private CIDR lists"
  type        = list(string)
  default     = ["eu-central-1a", "eu-central-1b"]
}

variable "enable_nat_gateway" {
  description = "Create a NAT Gateway per public subnet so private subnets can reach the internet"
  type        = bool
  default     = true
}

variable "enable_flow_logs" {
  description = "Enable VPC Flow Logs to CloudWatch Logs for network traffic visibility and security auditing"
  type        = bool
  default     = true
}

variable "enable_vpc_endpoints" {
  description = "Create VPC Gateway Endpoints for S3 and DynamoDB to avoid NAT Gateway data-transfer costs (not yet implemented)"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Map of additional tags to merge onto all resources created by this module"
  type        = map(string)
  default     = {}
}
