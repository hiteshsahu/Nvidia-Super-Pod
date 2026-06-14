# Workloads — NVIDIA SuperPod

Optional GPU workloads to run after the core stack (GPU Operator + Prometheus + Grafana) is healthy. Each workload runs independently and can be applied in any order.

---

## Directory Structure

```
workloads/
├── cuda/
│   ├── cuda-test.sh        # Validation script (edit this)
│   ├── cuda-test.yaml      # Kubernetes Job + ServiceAccount
│   └── Dockerfile          # Local Docker image with compiled CUDA samples
├── pytorch/
│   ├── benchmark.py        # Benchmark script (edit this)
│   ├── requirements.txt    # Local pip dependencies
│   └── pytorch-job.yaml    # Kubernetes Job + ServiceAccount
└── triton/
    └── triton.yaml         # Deployment + Service + ServiceMonitor
```

---

## Prerequisites

Core stack must be running before applying any example:

```bash
kubectl get nodes -o jsonpath='{.items[*].status.allocatable.nvidia\.com/gpu}'
# Expected: 1
```

---

## CUDA Validation

Confirms GPU access end-to-end: `nvidia-smi` → `deviceQuery` → `bandwidthTest`.

### Run locally (Docker)

`deviceQuery` and `bandwidthTest` are not in the base CUDA image — the `Dockerfile` compiles them from source so local output matches AWS exactly.

```bash
# Build once (compiles CUDA samples inside the image — takes ~3 min)
docker build -t cuda-validation workloads/cuda/

# Run (requires NVIDIA Container Toolkit or Docker Desktop with GPU support)
docker run --rm --gpus all cuda-validation
```

To iterate on the script without rebuilding the image:
```bash
docker run --rm --gpus all \
  -v $(pwd)/workloads/cuda/cuda-test.sh:/scripts/cuda-test.sh:ro \
  cuda-validation
```

### Run on Kubernetes (AWS)

```bash
# 1. Push script into cluster
kubectl create configmap cuda-test-script \
  --from-file=cuda-test.sh=workloads/cuda/cuda-test.sh \
  --namespace training --dry-run=client -o yaml | kubectl apply -f -

# 2. Run the job
kubectl apply -f workloads/cuda/cuda-test.yaml
kubectl logs -n training job/cuda-validation -f

# Cleanup
kubectl delete job cuda-validation -n training
```

**Expected output:**

```
All GPU validation checks PASSED.
```

---

## PyTorch ResNet-50 Benchmark

Measures ResNet-50 forward+backward throughput and step latency.

### Run locally

```bash
pip install -r workloads/pytorch/requirements.txt

# GTX 4060 — 8 GB VRAM
BATCH_SIZE=32 python3 workloads/pytorch/benchmark.py

# T4 — 16 GB VRAM (AWS default)
python3 workloads/pytorch/benchmark.py
```

### Run on Kubernetes (AWS)

```bash
# 1. Push script into cluster
kubectl create configmap pytorch-benchmark-script \
  --from-file=benchmark.py=workloads/pytorch/benchmark.py \
  --namespace training --dry-run=client -o yaml | kubectl apply -f -

# 2. Run the job
kubectl apply -f workloads/pytorch/pytorch-job.yaml
kubectl logs -n training job/pytorch-benchmark -f

# Cleanup
kubectl delete job pytorch-benchmark -n training
```

### Tuning via environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `BATCH_SIZE` | `64` | Input batch size — reduce to `32` for 8 GB VRAM |
| `WARMUP_STEPS` | `5` | Steps before timing starts |
| `TIMED_STEPS` | `50` | Steps used to calculate throughput |

Override on the command line:
```bash
BATCH_SIZE=32 TIMED_STEPS=20 python3 workloads/pytorch/benchmark.py
```

Or edit the env vars in `pytorch-job.yaml` before applying to Kubernetes.

**Expected output (T4, batch=64):**

```
Throughput  : ~320 samples / sec
Latency     : ~200 ms / step
```

---

## Triton Inference Server

Takes trained ML models and exposes them as a production inference API on the GPU node. Triton loads models from a shared directory (`/mnt/data/model-repository`) and serves them over three protocols simultaneously:

| Port | NodePort | Protocol | Use |
|------|----------|----------|-----|
| 8000 | 30800 | HTTP/REST | Standard inference requests |
| 8001 | 30801 | gRPC | High-throughput clients |
| 8002 | 30802 | Prometheus | Scraped by kube-prometheus-stack |

Supported backends: TensorRT, ONNX Runtime, PyTorch, TensorFlow — drop the model file in and Triton handles the rest.

### Key config choices

| Flag | Value | Reason |
|------|-------|--------|
| `--exit-on-error` | `false` | One bad model won't take down the whole server |
| `--strict-model-config` | `false` | Triton infers config from the model file if `config.pbtxt` is absent |
| `/dev/shm` mount | 4 GiB | Zero-copy IPC between client and server — avoids a GPU→CPU→GPU round-trip |

### Model repository layout

Place models on the host before applying:

```
/mnt/data/model-repository/
└── <model-name>/
    ├── config.pbtxt          # optional with --strict-model-config=false
    └── 1/
        └── model.plan        # TensorRT engine, or model.onnx / model.pt
```

### Deploy

```bash
kubectl apply -f workloads/triton/triton.yaml
kubectl rollout status deployment/triton -n inference
```

### Access

```bash
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}')

# Health check
curl http://$NODE_IP:30800/v2/health/ready

# List loaded models
curl http://$NODE_IP:30800/v2/models

# Metrics (scraped automatically by Prometheus via ServiceMonitor)
curl http://$NODE_IP:30802/metrics
```

| Endpoint | NodePort | Protocol |
|----------|----------|----------|
| HTTP inference | 30800 | HTTP |
| gRPC inference | 30801 | gRPC |
| Prometheus metrics | 30802 | HTTP |

### Teardown

```bash
kubectl delete -f workloads/triton/triton.yaml
```

---

## Local vs AWS — Quick Reference

| Step | Local (WSL2 / Linux) | AWS (Kubernetes) |
|------|----------------------|------------------|
| CUDA validation | Not applicable — run `nvidia-smi` directly | `kubectl apply` + ConfigMap |
| PyTorch benchmark | `python3 benchmark.py` | `kubectl apply` + ConfigMap |
| Triton | Docker: `docker run --gpus all nvcr.io/nvidia/tritonserver:24.01-py3` | `kubectl apply -f triton.yaml` |
