# 🐸 NVIDIA SuperPod — GPU Infrastructure Lab

> A hands-on infrastructure project simulating enterprise-grade NVIDIA GPU cluster provisioning, orchestration, and observability — built to demonstrate real-world AI infrastructure skills across the full stack: bare metal → Kubernetes → monitoring.

---

## 📋 Overview

This project provisions and operates a GPU-accelerated infrastructure stack modelled after NVIDIA's DGX SuperPod reference architecture. It covers driver management, CUDA toolkit integration, Kubernetes GPU orchestration via the NVIDIA GPU Operator, and end-to-end observability using DCGM Exporter, Prometheus, and Grafana.

**Target environments:**
- AWS EC2 GPU instances (`g4dn.xlarge` / `p3.2xlarge`)
- Local Kubernetes clusters (kind / minikube with GPU passthrough)
- Expandable to bare-metal Linux nodes

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    NVIDIA SuperPod Lab                   │
├─────────────────────────────────────────────────────────┤
│                                                         │
│   ┌──────────────┐     ┌──────────────────────────┐    │
│   │  Provisioning │     │     Kubernetes Layer      │    │
│   │              │     │                          │    │
│   │  - Terraform  │────▶│  - NVIDIA GPU Operator   │    │
│   │  - Ansible    │     │  - Device Plugin         │    │
│   │  - Cloud Init │     │  - Node Feature Discovery│    │
│   └──────────────┘     └──────────┬───────────────┘    │
│                                   │                     │
│   ┌──────────────┐     ┌──────────▼───────────────┐    │
│   │  GPU Layer   │     │    Observability Stack    │    │
│   │              │     │                          │    │
│   │  - Drivers   │     │  - DCGM Exporter         │    │
│   │  - CUDA 12.x │     │  - Prometheus            │    │
│   │  - cuDNN     │     │  - Grafana Dashboards    │    │
│   │  - nvidia-smi│     │  - Alerting Rules        │    │
│   └──────────────┘     └──────────────────────────┘    │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

---

## 🛠️ Stack

| Layer | Technology |
|---|---|
| Cloud | AWS EC2 (`g4dn`, `p3`) |
| IaC | Terraform |
| Configuration Management | Ansible |
| Container Orchestration | Kubernetes (EKS / kind) |
| GPU Operator | NVIDIA GPU Operator |
| GPU Monitoring | DCGM Exporter |
| Metrics | Prometheus |
| Dashboards & Alerts | Grafana |
| Workloads | PyTorch, CUDA Samples, Triton Inference Server |
| Profiling | Nsight Systems, `nvidia-smi` |

---

## 📁 Project Structure

```
nvidia-superpod/
├── terraform/
│   ├── main.tf                    # Root: VPC + GPU node wiring
│   ├── variables.tf               # All input variables with descriptions
│   ├── outputs.tf                 # Useful outputs (IPs, URLs, commands)
│   └── modules/
│       ├── vpc/                   # VPC, subnets, IGW, NAT GW, flow logs
│       └── gpu-node/              # EC2, EBS, IAM, SG, EIP, CW alarms
├── kubernetes/
│   ├── base/
│   │   └── namespaces.yaml        # gpu-operator, monitoring, inference, training
│   ├── gpu-operator/
│   │   └── values.yaml            # GPU Operator Helm values (driver.enabled=false)
│   ├── dcgm-exporter/
│   │   └── values.yaml            # DCGM Exporter Helm values + ServiceMonitor
│   ├── workloads/
│   │   ├── cuda-test.yaml         # Job: nvidia-smi, deviceQuery, bandwidthTest
│   │   ├── pytorch-job.yaml       # Job: ResNet-50 throughput benchmark
│   │   └── triton.yaml            # Deployment + Service + ServiceMonitor
│   └── monitoring/
│       ├── prometheus/
│       │   └── values.yaml        # kube-prometheus-stack Helm values
│       └── grafana/
│           └── dashboards/
│               └── gpu-cluster.json  # 11-panel GPU metrics dashboard
├── runbooks/
│   ├── 01-driver-install.md       # Manual driver install & validation
│   ├── 02-cuda-setup.md           # CUDA 12-3 setup & cuDNN
│   ├── 03-gpu-operator.md         # GPU Operator deploy & verify
│   └── 04-observability.md        # DCGM + Prometheus + Grafana
└── docs/
    ├── architecture.md            # Full layer diagram & design decisions
    ├── benchmarks.md              # T4 bandwidth, compute, DCGM baselines
    └── lessons-learned.md         # Operational lessons from building this stack
```

---

## 🚀 Getting Started

### Prerequisites

```bash
# Required tools
terraform >= 1.5
ansible >= 2.14
kubectl >= 1.28
helm >= 3.12
aws-cli >= 2.x
```

### 1. Provision GPU Node on AWS

```bash
cd terraform/
terraform init
terraform plan -var="instance_type=g4dn.xlarge"
terraform apply
```

### 2. Validate GPU Setup (drivers + CUDA installed automatically by cloud-init)

```bash
./scripts/validate-gpu.sh

# Expected output:
# ✅ nvidia-smi: NVIDIA T4 detected
# ✅ CUDA 12.x toolkit installed
# ✅ deviceQuery: PASSED
# ✅ bandwidthTest: Host-to-Device 12.5 GB/s
```

### 3. Bootstrap Kubernetes namespaces

```bash
kubectl apply -f kubernetes/base/namespaces.yaml
```

### 4. Deploy GPU Operator

```bash
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia && helm repo update

# Label the node first (required on single-node clusters)
kubectl label node $(kubectl get nodes -o jsonpath='{.items[0].metadata.name}') \
  nvidia.com/gpu.present=true

helm install gpu-operator nvidia/gpu-operator \
  --namespace gpu-operator \
  --version v24.3.0 \
  -f kubernetes/gpu-operator/values.yaml \
  --wait --timeout=10m
```

### 5. Verify GPU Resources in Kubernetes

```bash
kubectl get nodes -o json | jq '.items[].status.allocatable | select(."nvidia.com/gpu")'
# Expected: { "nvidia.com/gpu": "1" }

# CUDA validation job
kubectl apply -f kubernetes/workloads/cuda-test.yaml
kubectl logs -n training job/cuda-validation -f
# Expected last line: All GPU validation checks PASSED.
```

### 6. Deploy Observability Stack

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# kube-prometheus-stack (Prometheus + Grafana + node-exporter)
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  -f kubernetes/monitoring/prometheus/values.yaml \
  --wait --timeout=10m

# DCGM Exporter (GPU hardware metrics)
helm install dcgm-exporter nvidia/dcgm-exporter \
  --namespace monitoring \
  --version 3.3.5 \
  -f kubernetes/dcgm-exporter/values.yaml \
  --wait

# Grafana is available at http://<node-ip>:30300  (admin / superpod-changeme)
```

---

## 📊 Key Metrics Monitored

| Metric | Description |
|---|---|
| `DCGM_FI_DEV_GPU_UTIL` | GPU compute utilization % |
| `DCGM_FI_DEV_MEM_COPY_UTIL` | Memory bandwidth utilization |
| `DCGM_FI_DEV_FB_USED` | GPU framebuffer memory used |
| `DCGM_FI_DEV_POWER_USAGE` | Power draw per GPU |
| `DCGM_FI_DEV_SM_CLOCK` | SM clock frequency |
| `DCGM_FI_DEV_GPU_TEMP` | GPU temperature |
| `DCGM_FI_DEV_NVLINK_BANDWIDTH_TOTAL` | NVLink bandwidth (multi-GPU) |

---

## 🔬 Workload Profiling

```bash
# Profile a PyTorch training job with Nsight Systems
./scripts/profile-workload.sh pytorch-job

# Quick utilization snapshot
nvidia-smi dmon -s u -d 1

# Continuous GPU stats
watch -n 1 nvidia-smi --query-gpu=utilization.gpu,utilization.memory,\
memory.used,memory.free,temperature.gpu,power.draw \
--format=csv,noheader,nounits
```

---

## 📖 Runbooks

Step-by-step operational guides live in `/runbooks/`:

- [Driver Installation & Validation](runbooks/01-driver-install.md)
- [CUDA Toolkit Setup](runbooks/02-cuda-setup.md)
- [GPU Operator Deployment](runbooks/03-gpu-operator.md)
- [Observability Stack Setup](runbooks/04-observability.md)
- [Troubleshooting Guide](runbooks/05-troubleshooting.md)

---

## 📈 Benchmark Results

| Test | Hardware | Result |
|---|---|---|
| Host-to-Device bandwidth | T4 (g4dn.xlarge) | ~12.5 GB/s |
| Device-to-Host bandwidth | T4 (g4dn.xlarge) | ~13.0 GB/s |
| CUDA deviceQuery | T4 | PASSED |
| PyTorch MNIST (1 epoch) | T4 | ~45s |

---

## 🎯 Key Learnings

- NVIDIA driver version must be compatible with the CUDA toolkit version — always verify the [CUDA compatibility matrix](https://docs.nvidia.com/cuda/cuda-toolkit-release-notes/) before provisioning
- The GPU Operator manages the full driver/toolkit/plugin lifecycle — prefer it over manual installation in Kubernetes environments
- DCGM Exporter requires `privileged: true` on the DaemonSet pod spec for hardware access
- Node Feature Discovery (NFD) labels nodes automatically — use `nvidia.com/gpu: "true"` selectors in workload specs
- GPU memory fragmentation is a common bottleneck in multi-tenant clusters — monitor `FB_USED` per workload carefully

---

## 🔗 References

- [NVIDIA GPU Operator Docs](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/index.html)
- [DCGM Exporter](https://github.com/NVIDIA/dcgm-exporter)
- [CUDA Compatibility Matrix](https://docs.nvidia.com/cuda/cuda-toolkit-release-notes/)
- [NVIDIA DGX SuperPod Reference Architecture](https://docs.nvidia.com/dgx-superpod/)
- [Kubernetes GPU Scheduling](https://kubernetes.io/docs/tasks/manage-gpus/scheduling-gpus/)

---

## 👤 Author

**Hitesh Sahu** — Senior Cloud Infrastructure & DevOps Architect
[hiteshsahu.com](https://hiteshsahu.com) · [LinkedIn](https://linkedin.com/in/hiteshsahu) · [GitHub](https://github.com/hiteshsahu)

> *Built as part of hands-on AI infrastructure exploration, aligned with NVIDIA DLI certifications in AI Infrastructure & Operations, Generative AI LLMs, and Agentic AI.*
