## Deploying Nvidia GPU CLuster on AWS EKS


### main.tf : the core infrastructure. 

Key design choices:
- Spot instance by default (`use_spot_instance = true`) — cuts cost from ~`$0.53/hr` to ~`$0.16/hr` on a T4, which matters for a lab project
- `IMDSv2 enforced` (http_tokens = "required") — security best practice NVIDIA will notice
- Separate data `EBS volume (200GB)` for datasets and model checkpoints — keeps root volume clean
- `CloudWatch alarm for low GPU` utilization for operational thinking, not just provisioning
- `IAM role with SSM access` — means you can shell in without opening SSH if needed

### variables.tf 
Validation blocks on instance_type and environment are deliberate. 

### outputs.tf 
Includes pre-built SSH command, all dashboard URLs, and a validate_gpu_command output.

After terraform apply you get everything you need printed directly.