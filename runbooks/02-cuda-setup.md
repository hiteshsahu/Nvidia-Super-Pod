# Runbook 02 — CUDA Toolkit Setup & Configuration

## Overview

On AWS, CUDA is installed automatically by cloud-init (`cuda-toolkit-12-3` via the `cuda-keyring` apt method). This runbook covers manual installation and post-install validation steps.

## Prerequisites

- NVIDIA driver 535 installed and validated (see [Runbook 01](01-driver-install.md))
- Ubuntu 22.04 LTS
- Driver >= 525 required for CUDA 12.x

---

## Steps

### 1. Add the NVIDIA CUDA apt repository

```bash
# Install the keyring package — this registers the CUDA apt repo and GPG key in one step.
wget -q https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb
sudo dpkg -i cuda-keyring_1.1-1_all.deb
sudo apt-get update -y
```

> Use `cuda-keyring_1.1-1_all.deb` (not `1.0`). The `1.0` package uses a deprecated apt-key path and conflicts with `1.1` if both are installed.

### 2. Install CUDA Toolkit 12-3

```bash
sudo apt-get install -y cuda-toolkit-12-3

# Verify the installed version
nvcc --version
# Expected: Cuda compilation tools, release 12.3
```

### 3. Set environment variables

Add to `/etc/environment` for system-wide availability (cloud-init does this automatically):

```bash
echo 'export PATH=/usr/local/cuda/bin:$PATH' | sudo tee -a /etc/environment
echo 'export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH' | sudo tee -a /etc/environment
source /etc/environment
```

Or for the current user only, add to `~/.bashrc`:

```bash
export PATH=/usr/local/cuda/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH
export CUDA_HOME=/usr/local/cuda
```

### 4. Install cuDNN (optional, recommended for deep learning)

cuDNN is available from the same CUDA apt repo — no manual tarball download required:

```bash
sudo apt-get install -y libcudnn8 libcudnn8-dev

# Verify
python3 -c "import ctypes; ctypes.CDLL('libcudnn.so.8'); print('cuDNN OK')"
```

### 5. Build and run CUDA validation samples

Cloud-init clones and pre-builds the samples at `/opt/cuda-samples`. To rebuild manually:

```bash
git clone --depth 1 https://github.com/NVIDIA/cuda-samples.git /opt/cuda-samples

# deviceQuery — reports all GPU properties
cd /opt/cuda-samples/Samples/1_Utilities/deviceQuery && make
./deviceQuery
# Expected last line: Result = PASS

# bandwidthTest — measures host↔device and device↔device memory bandwidth
cd /opt/cuda-samples/Samples/1_Utilities/bandwidthTest && make
./bandwidthTest --memory=pinned
# Expected: Host to Device ~12 GB/s, Device to Host ~13 GB/s (T4 PCIe Gen3 x16)
```

### 6. Validate with the Kubernetes job (once cluster is running)

```bash
kubectl apply -f workloads/cuda/cuda-test.yaml
kubectl logs -n training job/cuda-validation -f
# Expected last line: All GPU validation checks PASSED.
```

---

## Troubleshooting

**`nvcc: command not found`**
```bash
# Verify CUDA is on PATH
echo $PATH | tr ':' '\n' | grep cuda
# If missing, source the environment file
source /etc/environment
# Verify binary exists
ls /usr/local/cuda/bin/nvcc
```

**`libcuda.so.1: cannot open shared object file`**
```bash
# Run ldconfig to rebuild the dynamic linker cache
sudo ldconfig
# Or set manually
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:/usr/local/cuda/lib:$LD_LIBRARY_PATH
```

**`cuda-keyring` dpkg conflict**
```bash
# Remove both versions and reinstall the correct one
sudo apt-get remove --purge cuda-keyring
sudo dpkg -i cuda-keyring_1.1-1_all.deb
sudo apt-get update -y
```

**`nvcc` compilation fails with incompatible gcc**
```bash
# CUDA 12.3 requires gcc <= 12 on Ubuntu 22.04
gcc --version
sudo apt-get install -y gcc-12 g++-12
sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-12 60
```

---

## Next Steps

- Proceed to [Runbook 03](03-gpu-operator.md) — GPU Operator on Kubernetes
- Run the [PyTorch benchmark job](../workloads/pytorch/pytorch-job.yaml) to validate end-to-end compute
