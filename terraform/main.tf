####################################################################
# NVIDIA SuperPod Lab — Root Configuration
# Author : Hitesh Sahu (hiteshsahu.com)
####################################################################

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project     = "nvidia-superpod"
      Owner       = "hitesh-sahu"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

data "aws_availability_zones" "available" { state = "available" }

locals {
  common_tags = {
    Project     = "nvidia-superpod"
    Owner       = "hitesh-sahu"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

module "vpc" {
  source               = "./modules/vpc"
  name                 = "superpod"
  vpc_cidr             = "10.0.0.0/16"
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]
  availability_zones   = slice(data.aws_availability_zones.available.names, 0, 2)
  enable_nat_gateway   = true
  enable_flow_logs     = true
  enable_vpc_endpoints = false
  tags                 = local.common_tags
}

module "gpu_node_01" {
  source                 = "./modules/gpu-node"
  name                   = "superpod-node-01"
  vpc_id                 = module.vpc.vpc_id
  subnet_id              = module.vpc.public_subnet_ids[0]
  availability_zone      = data.aws_availability_zones.available.names[0]
  instance_type          = var.instance_type
  use_spot_instance      = var.use_spot_instance
  spot_max_price         = var.spot_max_price
  ssh_public_key         = var.ssh_public_key
  allowed_cidrs          = var.allowed_ssh_cidrs
  root_volume_size_gb    = var.root_volume_size_gb
  data_volume_size_gb    = var.data_volume_size_gb
  nvidia_driver_version  = var.nvidia_driver_version
  cuda_version           = var.cuda_version
  kubernetes_version     = var.kubernetes_version
  enable_dcgm_exporter   = true
  assign_elastic_ip      = true
  enable_placement_group = false
  data_bucket_name       = "superpod-data-${var.environment}"
  tags                   = local.common_tags
}
