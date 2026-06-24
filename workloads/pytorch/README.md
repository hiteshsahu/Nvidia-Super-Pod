# PyTorch ResNet-50 Benchmark 🐍

Measures GPU training throughput using a ResNet-50 forward+backward pass loop. Reports samples/sec and ms/step.

---

## 📂 Files

| File               | Purpose                                                            |
|--------------------|--------------------------------------------------------------------|
| `benchmark.py`     | Benchmark script — edit this to change model, batch size, or steps |
| `requirements.txt` | Local pip dependencies                                             |
| `pytorch-job.yaml` | Kubernetes Job + ServiceAccount                                    |

---

## ▶️ Run Locally

**Prerequisites:** Python 3.9+, NVIDIA driver, CUDA toolkit.

```bash
# Install dependencies
pip install -r workloads/pytorch/requirements.txt

# Run with defaults (batch=64, suits T4 16 GB)
python3 workloads/pytorch/benchmark.py

# GTX 4060 / any 8 GB GPU — reduce batch size
BATCH_SIZE=32 python3 workloads/pytorch/benchmark.py
```

### 🎛️ Tuning

All parameters are controlled by environment variables — no file edits needed.

| Variable       | Default | Description                                     |
|----------------|---------|-------------------------------------------------|
| `BATCH_SIZE`   | `64`    | Input batch size — reduce to `32` for 8 GB VRAM |
| `WARMUP_STEPS` | `5`     | Steps run before timing starts                  |
| `TIMED_STEPS`  | `50`    | Steps used to compute throughput and latency    |

```bash
BATCH_SIZE=32 WARMUP_STEPS=3 TIMED_STEPS=20 python3 workloads/pytorch/benchmark.py
```

---

## ☸️ Run on Kubernetes (AWS) 

The Job reads `benchmark.py` from a ConfigMap so the script can be updated without rebuilding any image.

```bash
# 1. Push script into the cluster (re-run after every benchmark.py edit)
kubectl create configmap pytorch-benchmark-script \
  --from-file=benchmark.py=workloads/pytorch/benchmark.py \
  --namespace training --dry-run=client -o yaml | kubectl apply -f -

# 2. Apply the Job
kubectl apply -f workloads/pytorch/pytorch-job.yaml

# 3. Follow logs
kubectl logs -n training job/pytorch-benchmark -f

# 4. Cleanup
kubectl delete job pytorch-benchmark -n training
```

To override batch size on Kubernetes, edit the `BATCH_SIZE` env var in `pytorch-job.yaml` before applying:

```yaml
env:
  - name: BATCH_SIZE
    value: "32"
```

---

## 📤 Expected Output

```
GPU      : Tesla T4
VRAM     : 16.0 GB
SMs      : 40
PyTorch  : 2.x.x
CUDA     : 12.3

Batch size   : 64
Warmup steps : 5
Timed steps  : 50

Warming up (5 steps)...
Benchmarking (50 steps, batch=64)...

Throughput  : ~320 samples / sec
Latency     : ~200 ms / step

Benchmark complete.
```

| Hardware                   | Batch | Throughput       | Latency      |
|----------------------------|-------|------------------|--------------|
| T4 16 GB (AWS g4dn.xlarge) | 64    | ~320 samples/sec | ~200 ms/step |
| GTX 4060 8 GB (local)      | 32    | ~400 samples/sec | ~80 ms/step  |

> GTX 4060 scores higher throughput at a smaller batch due to Ada Lovelace's higher FP32 throughput (15.1 vs 8.1
> TFLOPS), but the smaller batch means less work per step.

---

## How It Works

```
Local                               AWS (Kubernetes)
──────────────────────────────      ──────────────────────────────
pip install requirements.txt        ConfigMap ← benchmark.py
python3 benchmark.py                kubectl apply pytorch-job.yaml
  └─ reads BATCH_SIZE from env        └─ reads BATCH_SIZE from env
  └─ runs ResNet-50 loop              └─ runs ResNet-50 loop
  └─ prints throughput / latency      └─ prints throughput / latency
```

Same script, same output format — results are directly comparable between local and AWS.

---

## License
*© 2026 [Hitesh Kumar Sahu](https://hiteshsahu.com) · Licensed under [Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0)*
