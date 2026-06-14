# 📟 CUDA Validation

Validates end-to-end GPU access by running three checks in sequence:

| Check     | Tool             | What it confirms                |
|-----------|------------------|---------------------------------|
| Driver    | `nvidia-smi`     | Driver loaded, GPU visible      |
| Toolkit   | `nvcc --version` | CUDA compiler on PATH           |
| Device    | `deviceQuery`    | CUDA runtime, SM count, memory  |
| Bandwidth | `bandwidthTest`  | PCIe H2D / D2H / D2D throughput |

---

## 📂 Files

| File             | Purpose                                                                        |
|------------------|--------------------------------------------------------------------------------|
| `cuda-test.sh`   | Validation script — edit this to add or remove checks                          |
| `Dockerfile`     | Builds local image with `deviceQuery` and `bandwidthTest` compiled from source |
| `cuda-test.yaml` | Kubernetes Job + ServiceAccount                                                |

---

## 🐳 Run Locally (Docker)

The base CUDA image does not ship `deviceQuery` or `bandwidthTest`. The `Dockerfile` compiles them from
the [NVIDIA CUDA Samples](https://github.com/NVIDIA/cuda-samples) repo so local output is identical to what runs on AWS.

**Prerequisites:** Docker Desktop with GPU support enabled, or NVIDIA Container Toolkit on Linux/WSL2.

```bash
# Build — compiles CUDA samples inside the image (~3 min, once)
docker build -t cuda-validation workloads/cuda/

# Run
docker run --rm --gpus all cuda-validation
```

To edit `cuda-test.sh` and re-test without rebuilding the image:

```bash
docker run --rm --gpus all \
  -v $(pwd)/workloads/cuda/cuda-test.sh:/scripts/cuda-test.sh:ro \
  cuda-validation
```

**Expected output:**

```
============================================
 CUDA Validation — <date>
============================================

--- nvidia-smi ---
<GPU name, driver version, memory>

--- CUDA version ---
nvcc: NVIDIA (R) Cuda compiler driver ... release 12.3 ...

--- deviceQuery ---
Device 0: "<GPU name>"
  CUDA Capability Major/Minor version number: 7.5
  ...
  Result = PASS

--- bandwidthTest (H2D / D2H / D2D) ---
Host to Device Bandwidth   : ~12.0 GB/s
Device to Host Bandwidth   : ~12.8 GB/s
Device to Device Bandwidth : ~255.0 GB/s
Result = PASS

All GPU validation checks PASSED.
```

---

## ☸️ Run on Kubernetes (AWS)

The Job reads the script from a ConfigMap so you can update it without rebuilding anything.

```bash
# 1. Push script into the cluster (re-run after every cuda-test.sh edit)
kubectl create configmap cuda-test-script \
  --from-file=cuda-test.sh=workloads/cuda/cuda-test.sh \
  --namespace training --dry-run=client -o yaml | kubectl apply -f -

# 2. Apply the Job
kubectl apply -f workloads/cuda/cuda-test.yaml

# 3. Follow logs
kubectl logs -n training job/cuda-validation -f

# 4. Cleanup
kubectl delete job cuda-validation -n training
```

The Job auto-deletes its pod 10 minutes after completion (`ttlSecondsAfterFinished: 600`).

---

## How It Works

```
Local (Docker)                      AWS (Kubernetes)
──────────────────────────────      ──────────────────────────────
Dockerfile                          cloud-init
  └─ compiles deviceQuery             └─ compiles deviceQuery
       bandwidthTest                       bandwidthTest
       → /opt/cuda-samples                 → /opt/cuda-samples

docker run --gpus all               kubectl apply (Job)
  └─ mounts /scripts/cuda-test.sh     └─ mounts ConfigMap
       runs bash cuda-test.sh               runs bash cuda-test.sh
```

Both paths execute the same `cuda-test.sh` against the same binaries at the same path — output is directly comparable.
