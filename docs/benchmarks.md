# Benchmarks — NVIDIA SuperPod Lab

Hardware: AWS `g4dn.xlarge` — NVIDIA Tesla T4 (Turing, 16 GB GDDR6, 70W TDP, 2,560 CUDA cores, 320 Tensor cores)

---

## Memory Bandwidth (bandwidthTest, pinned memory)

| Transfer Direction | Bandwidth |
|--------------------|-----------|
| Host → Device (H2D) | ~12.0 GB/s |
| Device → Host (D2H) | ~12.8 GB/s |
| Device → Device (D2D) | ~255 GB/s |

T4 peak memory bandwidth spec is 300 GB/s (GDDR6). The D2D result of ~255 GB/s (85% efficiency) is typical for this test pattern. H2D/D2H are bounded by PCIe Gen3 x16 (~16 GB/s theoretical; pinned memory saturates it near 12–13 GB/s).

**Run:**
```bash
kubectl apply -f kubernetes/workloads/cuda-test.yaml
kubectl logs -n training job/cuda-validation | grep -A5 "Bandwidth Test"
```

---

## Compute Throughput (PyTorch ResNet-50 benchmark)

Workload: ResNet-50 forward + backward pass, batch size 64, float32, CUDA 12.3, PyTorch 24.01.

| Metric | Result |
|--------|--------|
| Throughput | ~320 samples / sec |
| Step latency | ~200 ms / step (batch=64) |
| GPU utilization (during run) | 85–95% |
| VRAM used | ~4.2 GB / 16 GB |
| Power draw | 60–68W |
| GPU temperature | 55–65°C |

**Run:**
```bash
kubectl apply -f kubernetes/workloads/pytorch-job.yaml
kubectl logs -n training job/pytorch-benchmark -f
```

---

## DCGM — Idle vs Active Baseline

Taken from Grafana during a 60-second training window vs idle:

| Metric | Idle | Active (ResNet-50) |
|--------|------|--------------------|
| `DCGM_FI_DEV_GPU_UTIL` | 0% | 85–95% |
| `DCGM_FI_DEV_MEM_COPY_UTIL` | 0% | 15–25% |
| `DCGM_FI_DEV_FB_USED` | ~350 MiB | ~4,300 MiB |
| `DCGM_FI_DEV_GPU_TEMP` | 35°C | 55–65°C |
| `DCGM_FI_DEV_POWER_USAGE` | 8W | 62–68W |
| `DCGM_FI_DEV_SM_CLOCK` | 300 MHz | 1,590 MHz |
| `DCGM_FI_DEV_MEM_CLOCK` | 405 MHz | 5,001 MHz |

---

## deviceQuery — GPU Capabilities

```
Device 0: "Tesla T4"
  CUDA Capability Major/Minor version number:    7.5
  Total amount of global memory:                 15109 MBytes (15843524608 bytes)
  (40) Multiprocessors, (64) CUDA Cores/MP:     2560 CUDA Cores
  GPU Max Clock rate:                            1590 MHz (1.59 GHz)
  Memory Clock rate:                             5001 MHz
  Memory Bus Width:                              256-bit
  L2 Cache Size:                                 4194304 bytes
  Maximum Texture Dimension Size (x,y,z):        1D=(131072), 2D=(131072, 65536), 3D=(16384, 16384, 16384)
  Maximum Layered 1D Texture Size, (num) layers: 1D=(32768), 2048 layers
  Total amount of constant memory:               65536 bytes
  Total amount of shared memory per block:       49152 bytes
  Total number of registers available per block: 65536
  Warp size:                                     32
  Maximum number of threads per multiprocessor:  1024
  Maximum number of threads per block:           1024
  Max dimension size of a thread block (x,y,z): (1024, 1024, 64)
  Max dimension size of a grid size    (x,y,z): (2147483647, 65535, 65535)
  Concurrent copy and kernel execution:          Yes with 3 copy engine(s)
  Run time limit on kernels:                     No
  Integrated GPU sharing Host Memory:            No
  Support host page-locked memory mapping:       Yes
  Alignment requirement for Surfaces:            Yes
  Device has ECC support:                        Enabled
  Device supports Unified Addressing (UVA):      Yes
  Device supports Compute Preemption:            Yes
  Supports Cooperative Kernel Launch:            Yes
  Supports MultiDevice Co-op Kernel Launch:      Yes

Result = PASS
```

---

## Cost Reference (eu-central-1)

| Instance type | On-Demand | Spot (approx) | Monthly Spot (~720h) |
|---------------|-----------|---------------|----------------------|
| g4dn.xlarge | $0.526/hr | ~$0.16–0.20/hr | ~$115–$144 |
| g4dn.2xlarge | $0.752/hr | ~$0.23–0.28/hr | ~$166–$202 |
| g4dn.12xlarge (4× T4) | $3.912/hr | ~$1.20/hr | ~$864 |

Spot interruption rate for `g4dn.xlarge` in `eu-central-1` is typically < 5%. The Elastic IP and EBS volumes survive interruptions; only the instance itself terminates.
