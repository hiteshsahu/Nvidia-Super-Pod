####################################################################
# NVIDIA SuperPod — GPU Node Module
####################################################################

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  filter { name = "name",               values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"] }
  filter { name = "virtualization-type",values = ["hvm"] }
}

resource "aws_placement_group" "gpu_cluster" {
  count    = var.enable_placement_group ? 1 : 0
  name     = "${var.name}-pg"
  strategy = "cluster"
  tags     = merge(var.tags, { Name = "${var.name}-placement-group" })
}

resource "aws_security_group" "gpu_node" {
  name        = "${var.name}-sg"
  description = "GPU node security group"
  vpc_id      = var.vpc_id

  ingress { description = "SSH",            from_port = 22,   to_port = 22,   protocol = "tcp",cidr_blocks = var.allowed_cidrs }
  ingress { description = "Kubernetes API", from_port = 6443, to_port = 6443, protocol = "tcp",cidr_blocks = var.allowed_cidrs }
  ingress { description = "NodePort range", from_port = 30000,to_port = 32767,protocol = "tcp",cidr_blocks = var.allowed_cidrs }
  ingress { description = "Grafana",        from_port = 3000, to_port = 3000, protocol = "tcp",cidr_blocks = var.allowed_cidrs }
  ingress { description = "Prometheus",     from_port = 9090, to_port = 9090, protocol = "tcp",cidr_blocks = var.allowed_cidrs }
  ingress { description = "DCGM Exporter",  from_port = 9400, to_port = 9400, protocol = "tcp",cidr_blocks = var.allowed_cidrs }
  ingress { description = "Node Exporter",  from_port = 9100, to_port = 9100, protocol = "tcp",self = true }
  ingress { description = "Intra-cluster",  from_port = 0,    to_port = 0,    protocol = "-1", self = true }
  egress  { description = "All outbound",   from_port = 0,    to_port = 0,    protocol = "-1", cidr_blocks = ["0.0.0.0/0"] }

  tags = merge(var.tags, { Name = "${var.name}-sg" })
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals { type = "Service",identifiers = ["ec2.amazonaws.com"] }
  }
}

data "aws_iam_policy_document" "gpu_node_policy" {
  statement {
    sid     = "CloudWatchMetrics"
    actions = ["cloudwatch:PutMetricData","cloudwatch:GetMetricData","cloudwatch:ListMetrics"]
    resources = ["*"]
  }
  statement {
    sid     = "CloudWatchLogs"
    actions = ["logs:CreateLogGroup","logs:CreateLogStream","logs:PutLogEvents","logs:DescribeLogStreams"]
    resources = ["arn:aws:logs:*:*:*"]
  }
  statement {
    sid     = "S3DataAccess"
    actions = ["s3:GetObject","s3:PutObject","s3:ListBucket"]
    resources = ["arn:aws:s3:::${var.data_bucket_name}","arn:aws:s3:::${var.data_bucket_name}/*"]
  }
  statement {
    sid     = "ECRPull"
    actions = ["ecr:GetAuthorizationToken","ecr:BatchCheckLayerAvailability","ecr:GetDownloadUrlForLayer","ecr:BatchGetImage"]
    resources = ["*"]
  }
}

resource "aws_iam_role" "gpu_node" {
  name               = "${var.name}-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
  tags               = var.tags
}

resource "aws_iam_role_policy" "gpu_node" {
  name   = "${var.name}-policy"
  role   = aws_iam_role.gpu_node.id
  policy = data.aws_iam_policy_document.gpu_node_policy.json
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.gpu_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "gpu_node" {
  name = "${var.name}-profile"
  role = aws_iam_role.gpu_node.name
  tags = var.tags
}

resource "aws_key_pair" "this" {
  count      = var.ssh_public_key != "" ? 1 : 0
  key_name   = "${var.name}-key"
  public_key = var.ssh_public_key
  tags       = var.tags
}

resource "aws_ebs_volume" "data" {
  count             = var.data_volume_size_gb > 0 ? 1 : 0
  availability_zone = var.availability_zone
  size              = var.data_volume_size_gb
  type              = "gp3"
  iops              = 3000
  throughput        = 125
  encrypted         = true
  tags              = merge(var.tags, { Name = "${var.name}-data" })
}

resource "aws_instance" "gpu_node" {
  ami                    = var.ami_id != "" ? var.ami_id : data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.gpu_node.id]
  iam_instance_profile   = aws_iam_instance_profile.gpu_node.name
  key_name               = var.ssh_public_key != "" ? aws_key_pair.this[0].key_name : null
  placement_group        = var.enable_placement_group ? aws_placement_group.gpu_cluster[0].id : null

  dynamic "instance_market_options" {
    for_each = var.use_spot_instance ? [1] : []
    content {
      market_type = "spot"
      spot_options { max_price = var.spot_max_price,instance_interruption_behavior = "terminate" }
    }
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size_gb
    iops                  = 3000
    throughput            = 125
    encrypted             = true
    delete_on_termination = true
    tags                  = merge(var.tags, { Name = "${var.name}-root" })
  }

  user_data = base64encode(templatefile("${path.module}/templates/cloud-init.sh.tpl", {
    cuda_version       = var.cuda_version
    driver_version     = var.nvidia_driver_version
    k8s_version        = var.kubernetes_version
    node_name          = var.name
    enable_dcgm        = var.enable_dcgm_exporter
    data_volume_device = "/dev/sdf"
    data_volume_mount  = "/mnt/data"
  }))

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tags = merge(var.tags, { Name = "${var.name}" })
  lifecycle { ignore_changes = [ami, user_data] }
}

resource "aws_volume_attachment" "data" {
  count       = var.data_volume_size_gb > 0 ? 1 : 0
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.data[0].id
  instance_id = aws_instance.gpu_node.id
}

resource "aws_eip" "this" {
  count  = var.assign_elastic_ip ? 1 : 0
  domain = "vpc"
  tags   = merge(var.tags, { Name = "${var.name}-eip" })
}

resource "aws_eip_association" "this" {
  count         = var.assign_elastic_ip ? 1 : 0
  instance_id   = aws_instance.gpu_node.id
  allocation_id = aws_eip.this[0].id
}

resource "aws_cloudwatch_metric_alarm" "gpu_util_low" {
  alarm_name          = "${var.name}-gpu-util-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 3
  metric_name         = "GPUUtilization"
  namespace           = "SuperPod/GPU"
  period              = 300
  statistic           = "Average"
  threshold           = 10
  alarm_description   = "GPU utilization below 10% — idle or stalled workload"
  treat_missing_data  = "notBreaching"
  dimensions          = { InstanceId = aws_instance.gpu_node.id }
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "gpu_mem_high" {
  alarm_name          = "${var.name}-gpu-mem-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "GPUMemoryUsed"
  namespace           = "SuperPod/GPU"
  period              = 60
  statistic           = "Average"
  threshold           = 90
  alarm_description   = "GPU memory above 90% — OOM risk"
  treat_missing_data  = "notBreaching"
  dimensions          = { InstanceId = aws_instance.gpu_node.id }
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "gpu_temp_high" {
  alarm_name          = "${var.name}-gpu-temp-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "GPUTemperature"
  namespace           = "SuperPod/GPU"
  period              = 60
  statistic           = "Maximum"
  threshold           = 83
  alarm_description   = "GPU temperature above 83C — thermal throttle risk"
  treat_missing_data  = "notBreaching"
  dimensions          = { InstanceId = aws_instance.gpu_node.id }
  tags                = var.tags
}
