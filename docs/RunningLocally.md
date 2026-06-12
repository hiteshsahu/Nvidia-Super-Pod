# Running Locally — NVIDIA SuperPod Lab

---

## Windows Support (GTX / RTX Consumer GPU)

### Tested configuration

| Component  | Specification                          |
|------------|----------------------------------------|
| OS         | Windows 10 22H2 / Windows 11           |
| GPU        | NVIDIA GTX 4060 (Ada Lovelace, SM 8.9) |
| VRAM       | 8 GB GDDR6                             |
| Driver     | 535+ (Game Ready or Studio)            |
| Runtime    | WSL2 + Ubuntu 22.04 + Docker Desktop   |
| Kubernetes | Docker Desktop built-in                |

### GTX 4060 vs T4 — what differs

| Property                 | T4 (AWS)            | GTX 4060 (Windows)         |
|--------------------------|---------------------|----------------------------|
| Architecture             | Turing SM 7.5       | Ada Lovelace SM 8.9        |
| VRAM                     | 16 GB               | **8 GB**                   |
| FP32 throughput          | 8.1 TFLOPS          | 15.1 TFLOPS                |
| TDP                      | 70 W                | **115 W**                  |
| Hardware ECC             | ✅                   | ❌ consumer card            |
| MIG                      | ❌                   | ❌                          |
| DCGM support             | Full                | Partial — ECC fields empty |
| GPU Operator driver mgmt | N/A (pre-installed) | ❌ Windows owns driver      |

### What works and what doesn't

| Component                 | Status | Action required                             |
|---------------------------|--------|---------------------------------------------|
| `nvidia-smi` in WSL2      | ✅      | None — inherited from Windows driver        |
| CUDA workloads            | ✅      | None                                        |
| Docker GPU containers     | ✅      | Docker Desktop with NVIDIA support          |
| Kubernetes GPU scheduling | ✅      | `nvidia.com/gpu.present=true` label on node |
| GPU Operator              | ✅      | `driver.enabled: false` already set         |
| DCGM Exporter             | ⚠️     | Works — ECC metrics always zero             |
| Prometheus + Grafana      | ✅      | Use `port-forward` instead of NodePort      |
| PyTorch benchmark         | ✅      | Reduce `BATCH = 64 → 32` for 8 GB VRAM      |
| Triton Inference Server   | ✅      | None                                        |
| Terraform / cloud-init    | ❌ Skip | AWS-only — not needed for local run         |
| Ansible playbook 01       | ❌ Skip | Docker Desktop provides Kubernetes          |

### Setup steps for Windows

**1. Install NVIDIA driver and verify WSL2 GPU access**

```powershell
# Install WSL2 with Ubuntu 22.04
wsl --install -d Ubuntu-22.04
```

```bash
# Inside WSL2 — GPU should be visible without any extra setup
nvidia-smi
# Expected: GeForce RTX 4060 with Windows driver version
```

**2. Enable Kubernetes in Docker Desktop**

Docker Desktop → Settings → Kubernetes → Enable Kubernetes → Apply & Restart

```bash
# Verify
kubectl get nodes
# Expected: docker-desktop   Ready   ...
```

**3. Verify Docker can access the GPU**

```bash
docker run --rm --gpus all nvidia/cuda:12.3.2-base-ubuntu22.04 nvidia-smi
```

**4. Label the local node**

```bash
kubectl label node docker-desktop nvidia.com/gpu.present=true
```

**5. Deploy the stack — skip playbooks 01 and Terraform**

```bash
# Apply namespaces
kubectl apply -f kubernetes/base/namespaces.yaml

# GPU Operator
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia && helm repo update
helm install gpu-operator nvidia/gpu-operator \
  --namespace gpu-operator --version v24.3.0 \
  -f kubernetes/gpu-operator/values.yaml \
  --wait --timeout=10m

# Observability
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  -f kubernetes/monitoring/prometheus/values.yaml
helm install dcgm-exporter nvidia/dcgm-exporter \
  --namespace monitoring \
  -f kubernetes/dcgm-exporter/values.yaml
```

**6. Access Grafana via port-forward (NodePort not needed locally)**

```bash
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
# Open http://localhost:3000  (admin / superpod-changeme)
```

**7. Adjust VRAM and alert thresholds for GTX 4060**

In `kubernetes/workloads/pytorch-job.yaml`:

```python
BATCH = 32          # reduced from 64 for 8 GB VRAM
```

In `kubernetes/monitoring/prometheus/values.yaml` PrometheusRule:

```yaml
- alert: GPUMemoryHigh
  expr: >
    100 * DCGM_FI_DEV_FB_USED /
    (DCGM_FI_DEV_FB_USED + DCGM_FI_DEV_FB_FREE) > 85  # 8 GB headroom is tighter
- alert: GPUHighTemperature
  expr: DCGM_FI_DEV_GPU_TEMP > 90  # GTX 4060 throttles at ~95°C, not 83°C
```

---

## Running in Isolation from Work (Windows)

If this project shares a machine with a work setup, use these boundaries to prevent any overlap.

### Isolation strategy

| Boundary         | Risk if shared                     | Solution                   |
|------------------|------------------------------------|----------------------------|
| AWS credentials  | Deploy into work account           | Separate named AWS profile |
| kubectl context  | `kubectl delete` hits work cluster | Separate kubeconfig file   |
| WSL2 environment | Work tools and config bleed in     | Dedicated WSL2 distro      |
| Docker context   | Work images / networks polluted    | Separate Docker context    |

### Dedicated WSL2 distro

```powershell
# Export a clean Ubuntu base then re-import under a project name
wsl --export Ubuntu-22.04 C:\WSL\ubuntu-base.tar
wsl --import superpod C:\WSL\superpod C:\WSL\ubuntu-base.tar --version 2

# Launch the isolated distro
wsl -d superpod
```

Your work WSL2 distro is completely untouched.

### Separate AWS profile

```bash
# Inside the superpod distro — never touch [default]
aws configure --profile superpod
# Enter your personal Access Key, Secret, region: eu-central-1

# Add to ~/.bashrc so it is always active in this distro
echo 'export AWS_PROFILE=superpod' >> ~/.bashrc

# Verify you are in your personal account before any terraform apply
aws sts get-caller-identity
```

### Separate kubeconfig

```bash
# Add to ~/.bashrc inside the superpod distro
echo 'export KUBECONFIG=~/.kube/superpod-config' >> ~/.bashrc
source ~/.bashrc

# Confirm — should show only your local cluster
kubectl config get-contexts
```

### Distro environment file (all isolation in one place)

```bash
# ~/.bashrc inside the superpod distro
export AWS_PROFILE=superpod
export KUBECONFIG=~/.kube/superpod-config
export TF_VAR_environment=lab

# Confirm account on every shell open
echo "AWS account: $(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo 'not configured')"
```

### Daily workflow

```powershell
# Open isolated environment
wsl -d superpod
# AWS = personal account, kubectl = local cluster only, no work config
```

```bash
# When done — destroy AWS resources and shut down
cd ~/Nvidia-Super-Pod/terraform && terraform destroy
exit
```

```powershell
# Terminate the distro process
wsl --terminate superpod
```

### Maximum isolation — separate Windows user account

For machines with MDM / endpoint monitoring managed by work IT:

1. Windows Settings → Accounts → Add account → Local account → `superpod-dev`
2. Log in as `superpod-dev`
3. Install WSL2, Docker Desktop, and all tooling fresh under that account
4. No shared credentials, no shared config, no shared Docker daemon

The GTX 4060 driver is shared at the hardware level across all Windows accounts — GPU access still works.

---

## Software Stack — installed automatically by cloud-init (AWS only)

| Software                 | Version   | Purpose                                |
|--------------------------|-----------|----------------------------------------|
| Ubuntu                   | 22.04 LTS | Base OS                                |
| NVIDIA Driver            | 535       | Minimum for CUDA 12.x (requires ≥ 525) |
| CUDA Toolkit             | 12-3      | GPU compute runtime                    |
| Docker CE                | latest    | Container runtime                      |
| NVIDIA Container Toolkit | latest    | GPU access inside containers           |
| kubectl                  | 1.29      | Kubernetes CLI                         |
| Helm                     | 3.x       | Package manager for Kubernetes         |
| kubeadm / kubelet        | 1.29      | Installed by Ansible playbook 01       |
| DCGM                     | latest    | GPU telemetry daemon                   |

On Windows, install the above manually inside the `superpod` WSL2 distro. The NVIDIA driver and CUDA are inherited from
Windows — do not reinstall them inside WSL2.

---

## Instance Upgrade Path (AWS)

Change `instance_type` in `terraform.tfvars` — no other code changes required.

| Use Case              | Instance        | GPU     | VRAM   | Spot ~price    |
|-----------------------|-----------------|---------|--------|----------------|
| Dev / lab (default)   | `g4dn.xlarge`   | 1× T4   | 16 GB  | $0.16–0.20 /hr |
| Larger batch sizes    | `g4dn.2xlarge`  | 1× T4   | 16 GB  | $0.23–0.28 /hr |
| Multi-GPU single node | `g4dn.12xlarge` | 4× T4   | 64 GB  | ~$1.20 /hr     |
| Production training   | `p3.2xlarge`    | 1× V100 | 16 GB  | $0.60–0.90 /hr |
| Large model training  | `p3.8xlarge`    | 4× V100 | 64 GB  | ~$2.40 /hr     |
| LLM fine-tuning       | `p4d.24xlarge`  | 8× A100 | 320 GB | ~$10 /hr       |
| Inference at scale    | `g5.xlarge`     | 1× A10G | 24 GB  | ~$0.40 /hr     |

> Switching to A100 (`p4d`) — enable MIG in `kubernetes/gpu-operator/values.yaml`:
> ```yaml
> migManager:
>   enabled: true
> mig:
>   strategy: single
> ```

---

## Cost Estimates (AWS eu-central-1)

| Mode                    | Hourly | Daily (8 h) | Monthly (720 h)   |
|-------------------------|--------|-------------|-------------------|
| `g4dn.xlarge` On-Demand | $0.526 | $4.21       | $379              |
| `g4dn.xlarge` Spot      | ~$0.18 | ~$1.44      | ~$130             |
| NAT Gateway ×2 baseline | —      | ~$2.10      | ~$64              |
| EBS gp3 300 GiB         | —      | ~$0.80      | ~$24              |
| **Spot total estimate** |        |             | **~$218 / month** |

> Run `terraform destroy` when not actively using the cluster. The only persistent cost when destroyed is the Elastic IP
> reservation (~$3.60/month if unattached — release it too if idle for long).

---

## Local Development Without AWS

### kind — manifest and Helm testing (no GPU)

```bash
brew install kind   # macOS / Linux

kind create cluster --name superpod-local
kubectl apply -f kubernetes/base/namespaces.yaml

helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring -f kubernetes/monitoring/prometheus/values.yaml

kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
# Grafana loads — no DCGM data since there is no GPU
```

GPU Operator and DCGM pods stay `Pending` — no `nvidia.com/gpu` resource. Everything else (namespaces, RBAC, Prometheus,
Grafana UI) works fully.

### Terraform plan only — zero cost preview

```bash
cd terraform/
terraform init
terraform plan -var="ssh_public_key=$(cat ~/.ssh/id_rsa.pub)"
# Previews every resource that would be created — no AWS charges incurred
```
