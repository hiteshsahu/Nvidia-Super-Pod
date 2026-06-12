# Hardware Requirements — NVIDIA SuperPod Lab

---

## Can I Run This Locally?

| Scenario                    | GPU Workloads | Kubernetes / Helm | Terraform Plan |
|-----------------------------|:-------------:|:-----------------:|:--------------:|
| Mac (Apple Silicon / Intel) |       ❌       | ✅ (kind/minikube) |       ✅        |
| Linux without NVIDIA GPU    |       ❌       | ✅ (kind/minikube) |       ✅        |
| Linux with NVIDIA GPU       |       ✅       |         ✅         |       ✅        |
| AWS EC2 g4dn / p3 / p4d     |       ✅       |         ✅         |       ✅        |

> Mac users can develop and test all manifests, Helm values, Ansible playbooks, and Terraform plans locally. GPU
> workloads need real NVIDIA hardware.

---

## Minimum AWS Configuration (as provisioned)

| Resource      | Specification                                      |
|---------------|----------------------------------------------------|
| Instance type | `g4dn.xlarge`                                      |
| GPU           | NVIDIA Tesla T4                                    |
| VRAM          | `16 GB GDDR6`                                      |
| CUDA Cores    | `2,560`                                            |
| Tensor Cores  | `320` (2nd gen)                                    |
| GPU TDP       | `70 W`                                             |
| vCPU          | `4 × Intel Cascade Lake`                           |
| RAM           | `16 GB DDR4`                                       |
| Network       | `Up to 25 Gbps`                                    |
| PCIe          | `Gen3 × 16`                                        |
| Root EBS      | `100 GiB gp3` — OS, drivers, Docker images         |
| Data EBS      | `200 GiB gp3` — models and datasets at `/mnt/data` |
| Elastic IP    | `1` — stable public address across stop/start      |

---

## Software Stack (installed automatically by cloud-init)

| Software                 | Version     | Purpose                                |
|--------------------------|-------------|----------------------------------------|
| Ubuntu                   | `22.04 LTS` | Base OS                                |
| NVIDIA Driver            | `535`       | Minimum for CUDA 12.x (requires ≥ 525) |
| CUDA Toolkit             | `12-3`      | GPU compute runtime                    |
| Docker CE                | `latest`    | Container runtime                      |
| NVIDIA Container Toolkit | `latest`    | GPU access inside containers           |
| kubectl                  | `1.29`      | Kubernetes CLI                         |
| Helm                     | `3.x`       | Package manager for Kubernetes         |
| kubeadm / kubelet        | `1.29`      | Installed by Ansible playbook 01       |
| DCGM                     | `latest`    | GPU telemetry daemon                   |

---

## GPU Capability Reference (Tesla T4)

| Property           | Value                          |
|--------------------|--------------------------------|
| Architecture       | Turing (SM 7.5)                |
| VRAM               | 16 GB GDDR6                    |
| Memory bandwidth   | 300 GB/s                       |
| FP32 throughput    | 8.1 TFLOPS                     |
| FP16 throughput    | 65 TFLOPS (Tensor Cores)       |
| INT8 throughput    | 130 TOPS                       |
| ECC                | Supported (enabled by default) |
| MIG                | Not supported                  |
| NVLink             | Not supported                  |
| PCIe H2D bandwidth | ~12 GB/s (Gen3 × 16)           |
| Max operating temp | 83 °C (throttle threshold)     |

---

## Instance Upgrade Path

Change `instance_type` in `terraform.tfvars` — no other code changes required.

```
instance_type = "g4dn.2xlarge"   # or p3.2xlarge, p4d.24xlarge, etc.
```

| Use Case              | Instance        | GPU     | VRAM         | Spot Price (eu-central-1) |
|-----------------------|-----------------|---------|--------------|---------------------------|
| Dev / lab (default)   | `g4dn.xlarge`   | 1× T4   | 16 GB        | ~$0.16–0.20 /hr           |
| Larger batch sizes    | `g4dn.2xlarge`  | 1× T4   | 16 GB        | ~$0.23–0.28 /hr           |
| Multi-GPU single node | `g4dn.12xlarge` | 4× T4   | 64 GB total  | ~$1.20 /hr                |
| Production training   | `p3.2xlarge`    | 1× V100 | 16 GB        | ~$0.60–0.90 /hr           |
| Large model training  | `p3.8xlarge`    | 4× V100 | 64 GB total  | ~$2.40 /hr                |
| LLM fine-tuning       | `p4d.24xlarge`  | 8× A100 | 320 GB total | ~$10 /hr                  |
| Inference at scale    | `g5.xlarge`     | 1× A10G | 24 GB        | ~$0.40 /hr                |

> When switching to A100 (`p4d`), enable MIG support in `kubernetes/gpu-operator/values.yaml`:
> ```yaml
> migManager:
>   enabled: true
> mig:
>   strategy: single
> ```

---

## Cost Estimates (eu-central-1)

| Mode                      | Hourly | Daily (8h) | Monthly (720h)    |
|---------------------------|--------|------------|-------------------|
| `g4dn.xlarge` On-Demand   | $0.526 | $4.21      | $379              |
| `g4dn.xlarge` Spot        | ~$0.18 | ~$1.44     | ~$130             |
| NAT Gateway (×2 baseline) | —      | ~$2.10     | ~$64              |
| EBS gp3 300 GiB           | —      | ~$0.80     | ~$24              |
| **Spot total estimate**   |        |            | **~$218 / month** |

> **Tip:** Run `terraform destroy` when not actively using the cluster. EBS volumes are deleted on termination in this
> config. The only persistent cost when destroyed is the Elastic IP reservation (~$3.60/month if unattached).

---

## Running Locally Without AWS

### Option A — kind (no GPU, manifest and Helm testing only)

```bash
brew install kind kubectl helm

kind create cluster --name superpod-local

kubectl apply -f kubernetes/base/namespaces.yaml

helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  -f kubernetes/monitoring/prometheus/values.yaml

# Grafana loads at localhost:3000 via port-forward — no DCGM data
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
```

GPU Operator and DCGM Exporter pods will stay `Pending` — no `nvidia.com/gpu` resource exists. Everything else (
namespaces, RBAC, Prometheus, Grafana UI) works fully.

### Option B — Linux machine with NVIDIA GPU

Install drivers and CUDA manually (see [Runbook 01](../runbooks/01-driver-install.md)
and [Runbook 02](../runbooks/02-cuda-setup.md)), then use `kubeadm` or `k3s` to bootstrap a local single-node cluster.
All GPU workloads will run identically to AWS.

```bash
# Bootstrap with k3s (lighter than kubeadm for local dev)
curl -sfL https://get.k3s.io | sh -
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Then follow the same Ansible / Helm deploy sequence
ansible-playbook ansible/playbooks/02-deploy-stack.yml
```

### Option C — Terraform plan only (no AWS spend)

```bash
cd terraform/
terraform init
terraform plan \
  -var="ssh_public_key=$(cat ~/.ssh/id_rsa.pub)" \
  -var="allowed_ssh_cidrs=[\"$(curl -s ifconfig.me)/32\"]"
# Previews all resources that would be created — no charges incurred
```

---

## Minimum Local Machine Requirements (for development)

| Resource | Minimum                           | Recommended                           |
|----------|-----------------------------------|---------------------------------------|
| OS       | macOS 13 / Ubuntu 22.04           | macOS 14+ / Ubuntu 22.04              |
| CPU      | 4 cores                           | 8+ cores                              |
| RAM      | 8 GB                              | 16 GB (kind cluster is memory-hungry) |
| Disk     | 20 GB free                        | 40 GB free                            |
| Tools    | terraform, kubectl, helm, ansible | + kind, docker, aws-cli               |
