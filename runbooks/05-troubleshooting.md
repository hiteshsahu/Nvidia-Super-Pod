# Runbook 05 — Troubleshooting Guide

## GPU Not Detected

### Symptoms
- `nvidia-smi` shows no GPUs
- Kubernetes node shows no GPU capacity
- Workloads cannot access GPU

### Diagnostics
```bash
# Check PCIe detection
lspci | grep -i nvidia

# Check kernel module loaded
lsmod | grep nvidia

# Check kernel errors
dmesg | grep -i nvidia | tail -20

# Check kernel module can load
sudo modprobe -v nvidia
```

### Solutions

**GPU not visible in lspci**
- Verify GPU is physically installed: check server logs or IPMI console
- Check BIOS settings: GPU should not be disabled
- Reboot and check again

**Kernel module not loading**
- Reinstall driver: `sudo apt-get install --reinstall nvidia-driver-535`
- Check secure boot status: `mokutil --sb-state` (should be disabled)
- Check dmesg for NVRM errors

**Device node missing**
```bash
# Recreate device nodes
sudo nvidia-smi
# If still missing, manually create:
sudo /usr/lib/nvidia-driver-535/bin/nvidia-smi
```

---

## CUDA Out of Memory (OOM)

### Symptoms
- PyTorch/TensorFlow errors: "CUDA out of memory"
- `nvidia-smi` shows memory full but no visible processes
- Jobs failing with memory allocation errors

### Diagnostics
```bash
# Check current memory usage
nvidia-smi --query-gpu=memory.used,memory.free,memory.total --format=csv

# Find processes using GPU memory
nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv

# Check if zombie processes exist
nvidia-smi | grep "<defunct>"
```

### Solutions

**Kill processes holding memory**
```bash
# Get PID of memory-holding process
nvidia-smi

# Kill it
sudo kill -9 <PID>

# Hard reset GPU (last resort)
sudo nvidia-smi --gpu-reset
```

**Reduce batch size in workload**
- Check job YAML for memory requests
- Reduce `batch_size` in training scripts
- Use gradient checkpointing/activation checkpointing

**Enable memory growth in TensorFlow**
```python
import tensorflow as tf
gpus = tf.config.list_physical_devices('GPU')
for gpu in gpus:
    tf.config.experimental.set_memory_growth(gpu, True)
```

---

## Docker Cannot Access GPU

### Symptoms
- Docker container can't find GPU
- nvidia-smi inside container returns "command not found"
- `--gpus all` flag doesn't work

### Diagnostics
```bash
# Check NVIDIA Container Toolkit installed
which nvidia-docker

# Check Docker NVIDIA runtime configured
docker info | grep nvidia

# Check host nvidia-smi works
nvidia-smi
```

### Solutions

**Install NVIDIA Container Toolkit**
```bash
# Remove old nvidia-docker
sudo apt-get remove nvidia-docker nvidia-docker2

# Install NVIDIA Container Toolkit
sudo apt-get install -y nvidia-container-toolkit

# Configure Docker runtime
sudo nvidia-ctk runtime configure --runtime=docker

# Restart Docker
sudo systemctl restart docker
```

**Test GPU access**
```bash
docker run --rm --gpus all ubuntu nvidia-smi

# If still fails, check runtime config
cat /etc/docker/daemon.json
# Should contain: "runtimes": {"nvidia": {...}}
```

---

## XID Errors (Hardware Faults)

### Symptoms
- System log spam with "XID nn: ERROR"
- GPU becomes unresponsive
- Random job failures or system resets

### Error Types
| XID | Meaning | Severity |
|-----|---------|----------|
| 13 | Graphics Engine Exception | Critical |
| 31 | GPU Memory Controller exception | Critical |
| 43 | GPU stopped responding | Critical |
| 61 | ECC error | Warning |
| 74 | NVLink error (multi-GPU) | Critical |
| 79 | GPU requires reset | Critical |

### Diagnostics
```bash
# Check current XID errors
nvidia-smi --query-gpu=ecc.errors.uncorrected.volatile.total --format=csv

# View system logs
sudo journalctl -u nvidia-smi -n 50

# Check DCGM health
dcgmi health -g 0 -c

# Check GPU temperatures (overheating causes errors)
nvidia-smi --query-gpu=index,temperature.gpu --format=csv
```

### Solutions

**Temporary: Reset GPU**
```bash
sudo nvidia-smi --gpu-reset
```

**Identify failing GPU**
```bash
# Note GPU index from nvidia-smi output
# Check which jobs are on that GPU
kubectl get pods -o json | jq '.items[] | select(.spec.nodeSelector["nvidia.com/gpu"])'
```

**Permanent: Replace GPU**
- Schedule maintenance window
- Drain node: `kubectl drain <node-name>`
- Physically replace GPU
- Verify replacement: `nvidia-smi`
- Uncordon node: `kubectl uncordon <node-name>`

---

## Kubernetes GPU Resource Unavailable

### Symptoms
- Pods requesting GPU stay Pending
- `kubectl describe node` shows no GPU capacity
- GPU Operator pods in CrashLoopBackOff

### Diagnostics
```bash
# Check node GPU capacity
kubectl describe node <node-name> | grep -A5 nvidia

# Check GPU Operator pods
kubectl get pods -n gpu-operator -o wide

# Check device plugin logs
kubectl logs -n gpu-operator -l app=nvidia-device-plugin-daemonset

# Check NFD labels
kubectl get node <node-name> --show-labels | grep nvidia
```

### Solutions

**Device plugin not running**
```bash
# Check pod status and logs
kubectl describe pod -n gpu-operator <device-plugin-pod>

# Restart device plugin
kubectl rollout restart daemonset/gpu-operator-nvidia-device-plugin-daemonset -n gpu-operator
```

**Missing NFD labels**
```bash
# Check for labels
kubectl get node <node-name> --show-labels | grep feature.node.kubernetes.io

# Force label manually (temporary workaround)
kubectl label node <node-name> nvidia.com/gpu.present=true --overwrite
kubectl label node <node-name> nvidia.com/gpu=1 --overwrite
```

**GPU not visible to kubelet**
```bash
# SSH to node and verify GPU:
nvidia-smi

# Restart kubelet
sudo systemctl restart kubelet

# Check kubelet logs
sudo journalctl -u kubelet -n 50
```

---

## DCGM Metrics Missing

### Symptoms
- DCGM exporter pod running but no metrics in Prometheus
- `curl http://localhost:9400/metrics` returns empty
- Grafana dashboard shows "No Data"

### Diagnostics
```bash
# Check DCGM service status
systemctl status nvidia-dcgm

# Check DCGM can access GPU
dcgmi discovery -l

# Verify exporter is running in k8s
kubectl get pods -n gpu-operator | grep dcgm

# Check exporter logs
kubectl logs -n gpu-operator -l app=dcgm-exporter
```

### Solutions

**DCGM service not running**
```bash
# Start DCGM
sudo systemctl start nvidia-dcgm
sudo systemctl enable nvidia-dcgm

# Verify
dcgmi health -g 0 -c
```

**DCGM can't access GPU**
```bash
# Reinstall DCGM
sudo apt-get remove -y datacenter-gpu-manager
sudo apt-get install -y datacenter-gpu-manager

# Restart
sudo systemctl restart nvidia-dcgm
```

**Exporter misconfigured in Kubernetes**
```bash
# Check service monitor
kubectl get servicemonitor -n gpu-operator

# Verify Prometheus scrape config
kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090
# Check http://localhost:9090/targets for dcgm endpoint
```

---

## Thermal Throttling

### Symptoms
- GPU clock frequency drops during intensive workloads
- Performance degrades over time
- Temperature stays near 80°C+

### Diagnostics
```bash
# Monitor temperature and clocks
nvidia-smi --query-gpu=index,temperature.gpu,clocks.gr,clocks.mem --format=csv -lms 100

# Check power limits
nvidia-smi --query-gpu=power.limit,power.draw --format=csv

# Check thermal design power
nvidia-smi --query-gpu=power.default_limit --format=csv
```

### Solutions

**Improve cooling**
- Check server airflow (fans running?)
- Clean GPU heatsinks of dust
- Increase fan speed if applicable

**Reduce power draw**
```bash
# Set max power limit (T4 = 70W typical)
sudo nvidia-smi -pm 1
sudo nvidia-smi -pl 70
```

**Spread workload across GPUs**
- Use multiple GPUs per job
- Distribute workloads across nodes
- Reduce concurrent workloads

---

## Performance Degradation

### Symptoms
- Similar workloads run slower over time
- GPU utilization appears high but throughput low
- Memory bandwidth seems throttled

### Diagnostics
```bash
# Run GPU benchmark
cuda-samples/bin/x86_64/linux/release/bandwidthTest

# Check memory errors
nvidia-smi --query-gpu=ecc.errors.uncorrected.aggregate.total --format=csv

# Monitor in real-time
nvidia-smi dmon
```

### Solutions

**Clear GPU cache/state**
```bash
sudo nvidia-smi --gpu-reset
```

**Check for GPU contention**
```bash
# List all GPU processes
nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv

# Kill unnecessary processes
sudo kill -9 <PID>
```

**Enable ECC if supported**
```bash
# Check if ECC capable
nvidia-smi -q | grep ECC

# Enable ECC (requires reboot)
sudo nvidia-smi -pm 1
sudo nvidia-smi -ecc 1
sudo reboot
```

---

## When to Escalate

Contact NVIDIA support if:
- XID errors persist after GPU reset
- Physical GPU replacement needed
- Performance issues not resolved by above steps
- Suspected hardware defect (failing SMART tests, etc.)

Gather logs before contacting support:
```bash
nvidia-debugdump -o /tmp/gpu_debug.log
sudo journalctl -u nvidia-dcgm > /tmp/dcgm.log
kubectl logs -n gpu-operator > /tmp/gpu-operator.log
```
