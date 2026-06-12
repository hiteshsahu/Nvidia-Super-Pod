# Runbook 02 — CUDA Toolkit Setup & Configuration

## Prerequisites
- NVIDIA driver installed and validated (see Runbook 01)
- Ubuntu 22.04 LTS
- Drivers >= 525 for CUDA 12.x compatibility

## Steps

### 1. Add NVIDIA CUDA repository
```bash
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-ubuntu2204.pin
sudo mv cuda-ubuntu2204.pin /etc/apt/preferences.d/cuda-repository-pin-600
```

### 2. Install CUDA Toolkit
```bash
sudo apt-get update
sudo apt-get install -y cuda-toolkit-12-4

# Or for a specific version:
# sudo apt-get install -y cuda-12-4
```

### 3. Set environment variables
Add to `~/.bashrc` or `/etc/environment`:
```bash
export PATH=/usr/local/cuda/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH
export CUDA_HOME=/usr/local/cuda
```

Apply changes:
```bash
source ~/.bashrc
```

### 4. Verify CUDA installation
```bash
nvcc --version
# Expected: CUDA Toolkit 12.4

cuda-memtest --stress
# Runs memory tests on all GPUs
```

### 5. Install cuDNN (optional but recommended)
```bash
# Download from https://developer.nvidia.com/cudnn
# Extract and copy files
tar -xzf cudnn-linux-x86_64-*.tar.xz
sudo cp cudnn-linux-x86_64-*/include/cudnn.h /usr/local/cuda/include/
sudo cp cudnn-linux-x86_64-*/lib/libcudnn* /usr/local/cuda/lib64/
sudo chmod a+r /usr/local/cuda/lib64/libcudnn*
```

### 6. Validate CUDA samples
```bash
cp -r /usr/local/cuda/samples ~/cuda-samples
cd ~/cuda-samples
make -j$(nproc)
./bin/x86_64/linux/release/deviceQuery
```

## Troubleshooting

**nvcc: command not found**
- Check PATH: `echo $PATH | grep cuda`
- Source bashrc: `source ~/.bashrc`
- Verify installation: `ls /usr/local/cuda/bin/`

**CUDA version mismatch**
- Check CUDA version: `nvcc --version`
- Check driver support: `nvidia-smi`
- Driver must support CUDA version (see compatibility matrix)

**libcuda.so.1 not found**
- Set LD_LIBRARY_PATH: `export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH`
- Run ldconfig: `sudo ldconfig`

**Compilation failures with nvcc**
- Ensure gcc/g++ are installed: `sudo apt-get install -y build-essential`
- Check CUDA architecture compatibility for your GPU

## Next Steps
- Proceed to Runbook 03 for GPU Operator deployment
- Install cuDNN for deep learning frameworks
- Set up containerized CUDA environments with Docker
