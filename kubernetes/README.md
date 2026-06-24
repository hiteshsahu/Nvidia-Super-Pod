# Kubernetes — NVIDIA SuperPod

All Kubernetes manifests and Helm values for the SuperPod GPU cluster. The stack runs on a single `g4dn.xlarge` node (Tesla T4) bootstrapped by Ansible playbook `01-bootstrap-k8s.yml`.

---


```mermaid

flowchart LR

    PROV["⚙️ Provisioning<br/>Terraform<br/>Ansible<br/>Cloud-Init"]

    K8S["☸️ Kubernetes Layer<br/>GPU Operator<br/>Device Plugin<br/>NFD"]

    GPU["🚀 GPU Layer<br/>Drivers<br/>CUDA<br/>cuDNN"]

    OBS["📊 Observability<br/>DCGM<br/>Prometheus<br/>Grafana"]

    PROV --> K8S
    K8S --> GPU
    K8S --> OBS

    classDef prov fill:#E3F2FD,stroke:#1565C0,stroke-width:2px;
    classDef k8s fill:#326CE5,color:#fff,stroke:#1A3F99,stroke-width:2px;
    classDef gpu fill:#76B900,color:#fff,stroke:#4C7A00,stroke-width:2px;
    classDef obs fill:#E8F5E9,stroke:#2E7D32,stroke-width:2px;

    class PROV prov;
    class K8S k8s;
    class GPU gpu;
    class OBS obs;



```

## Directory Structure

```
kubernetes/
├── base/
│   └── namespaces.yaml          # All namespaces — apply first
├── gpu-operator/
│   └── values.yaml              # NVIDIA GPU Operator Helm values
├── dcgm-exporter/
│   └── values.yaml              # DCGM Exporter Helm values
└── monitoring/
    ├── prometheus/
    │   └── values.yaml          # kube-prometheus-stack Helm values
    └── grafana/
        └── dashboards/
            └── gpu-cluster.json # 11-panel GPU metrics dashboard

workloads/                        # Optional — apply after core stack is healthy
├── cuda-test.yaml               # Job: GPU validation (nvidia-smi, deviceQuery, bandwidthTest)
├── pytorch-job.yaml             # Job: ResNet-50 throughput benchmark
└── triton.yaml                  # Deployment + Service + ServiceMonitor
```

---

## Namespace Layout

| Namespace | Contents |
|-----------|----------|
| `gpu-operator` | GPU Operator, device plugin, GFD, DCGM daemon, validator |
| `monitoring` | DCGM Exporter, Prometheus, Grafana, node-exporter |
| `inference` | Triton Inference Server |
| `training` | CUDA validation job, PyTorch benchmark job |

---

## Deployment Workflow

```mermaid
flowchart TD
    START([Kubernetes node Ready\nAnsible playbook 01 complete])

    subgraph NS["Step 1 · Namespaces"]
        NS1[kubectl apply -f base/namespaces.yaml\nCreates 4 namespaces]
    end

    subgraph GPU["Step 2 · GPU Operator  —  namespace: gpu-operator"]
        G1[helm install gpu-operator\nnvidia/gpu-operator v24.3.0]
        G2[device-plugin DaemonSet\nexposes nvidia.com/gpu resource]
        G3[GPU Feature Discovery\nlabels node with GPU model + CUDA version]
        G4[DCGM daemon\nCollects hardware telemetry]
        G5{nvidia.com/gpu\nin allocatable?}
        G1 --> G2 & G3 & G4 --> G5
    end

    subgraph OBS["Step 3 · Observability  —  namespace: monitoring"]
        O1[helm install prometheus\nprometheus-community/kube-prometheus-stack 58.x]
        O2[Prometheus\nscrapes all ServiceMonitors]
        O3[Grafana :30300\n11-panel GPU dashboard]
        O4[node-exporter\nhost metrics]
        O5[helm install dcgm-exporter\nnvidia/dcgm-exporter 3.3.5]
        O6[ServiceMonitor CR\nwires DCGM --> Prometheus]
        O7[DCGM metrics visible\nin Grafana]
        O1 --> O2 & O3 & O4
        O5 --> O6 --> O2
        O2 --> O7
    end

    subgraph WL["Step 4 · Workloads"]
        direction TB
        subgraph VAL["Validation  —  namespace: training"]
            W1[kubectl apply cuda-test.yaml]
            W2["Job: cuda-validation\nnvidia-smi · deviceQuery · bandwidthTest"]
            W3{All checks\nPASSED?}
            W1 --> W2 --> W3
        end

        subgraph INF["Inference  —  namespace: inference"]
            W4[kubectl apply triton.yaml]
            W5["Deployment: triton\nnvcr.io/nvidia/tritonserver:24.01-py3"]
            W6["NodePort Service\nHTTP :30800 · gRPC :30801 · metrics :30802"]
            W7[ServiceMonitor\nPrometheus scrapes Triton metrics]
            W4 --> W5 --> W6
            W5 --> W7
        end

        subgraph BENCH["Benchmark  —  namespace: training  optional"]
            W8[kubectl apply pytorch-job.yaml]
            W9[Job: pytorch-benchmark\nResNet-50 forward+backward]
            W10[Reports samples/sec\nand ms/step]
            W8 --> W9 --> W10
        end

        W3 -->|yes| W4
        W3 -->|no| FAIL(["Abort — fix GPU issue first"])
    end

    subgraph METRICS["Metrics Data Flow"]
        direction LR
        M1[T4 Hardware]
        M2[DCGM daemon]
        M3[dcgm-exporter :9400]
        M4[Prometheus]
        M5[Grafana dashboard]
        M1 --> M2 --> M3 -->|ServiceMonitor 15s scrape| M4 --> M5
    end

    START --> NS --> GPU
    G5 -->|yes| OBS
    G5 -->|no — wait| G5
    OBS --> WL
    WL --> METRICS
    METRICS --> DONE([Stack Operational])
```

---

## Install Commands

### Step 1 — Namespaces

```bash
kubectl apply -f kubernetes/base/namespaces.yaml
```

### Step 2 — GPU Operator

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

# Verify
kubectl get nodes -o jsonpath='{.items[*].status.allocatable.nvidia\.com/gpu}'
# Expected: 1
```

### Step 3 — Observability

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --version 58.7.2 \
  -f kubernetes/monitoring/prometheus/values.yaml \
  --wait --timeout=10m

helm install dcgm-exporter nvidia/dcgm-exporter \
  --namespace monitoring \
  --version 3.3.5 \
  -f kubernetes/dcgm-exporter/values.yaml \
  --wait
```

Access Grafana on **NodePort 30300** — default credentials `admin / superpod-changeme`.

To import the GPU dashboard:
```bash
# Grafana UI → Dashboards → Import → Upload kubernetes/monitoring/grafana/dashboards/gpu-cluster.json
```

### Step 4 — Workloads

```bash
# CUDA validation (run first — aborts if GPU is broken)
kubectl apply -f workloads/cuda/cuda-test.yaml
kubectl wait job/cuda-validation -n training --for=condition=complete --timeout=5m
kubectl logs -n training job/cuda-validation

# Triton Inference Server
kubectl apply -f workloads/triton/triton.yaml
kubectl rollout status deployment/triton -n inference

# PyTorch benchmark (optional)
kubectl apply -f workloads/pytorch/pytorch-job.yaml
kubectl logs -n training job/pytorch-benchmark -f
```

---

## Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| `driver.enabled: false` in GPU Operator | Driver is pre-installed by cloud-init before Kubernetes exists — letting the operator install it again causes a version-check conflict |
| DCGM Exporter in `monitoring` not `gpu-operator` | Co-locates all observability components; the `ServiceMonitor` `release: prometheus` label must match the kube-prometheus-stack release name |
| `serviceMonitorSelectorNilUsesHelmValues: false` | Without this, Prometheus only scrapes ServiceMonitors in its own namespace and silently ignores DCGM |
| Triton uses `hostPath` for model repository | Models are written to `/mnt/data` on the EBS volume by training jobs; Triton reads them directly without a PVC |
| `emptyDir medium: Memory` for `/dev/shm` | Triton and PyTorch use shared memory for zero-copy data transfer; the default 64 MiB `/dev/shm` is too small for GPU workloads |
| NodePort over LoadBalancer | Single-node lab — no cloud load balancer needed; NodePort ports are pinned so URLs stay stable |

---

## Port Reference

| Service | NodePort | Protocol | Path |
|---------|----------|----------|------|
| Grafana | 30300 | HTTP | `/` |
| Triton HTTP | 30800 | HTTP | `/v2/health/ready` |
| Triton gRPC | 30801 | gRPC | — |
| Triton metrics | 30802 | HTTP | `/metrics` |
| Prometheus | ClusterIP only | HTTP | port-forward 9090 |
| DCGM Exporter | ClusterIP only | HTTP | port-forward 9400 |

---

## License
*© 2026 [Hitesh Kumar Sahu](https://hiteshsahu.com) · Licensed under [Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0)*
