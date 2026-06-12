# Runbook 01 — NVIDIA Driver Installation & Validation

## Prerequisites
- Ubuntu 22.04 LTS
- AWS g4dn.xlarge (T4 GPU) or equivalent
- Root or sudo access

## Steps

### 1. Verify GPU is detected by the system
```bash
lspci | grep -i nvidia
# Expected: NVIDIA Corporation TU104GL [Tesla T4]
```

### 2. Install driver
```bash
sudo apt-get update
sudo apt-get install -y nvidia-driver-535
sudo reboot
```

### 3. Validate after reboot
```bash
nvidia-smi
# Expected: table showing GPU name, driver version, CUDA version
```

### 4. Check driver version compatibility
```bash
nvidia-smi --query-gpu=driver_version --format=csv,noheader
# Must be >= 525 for CUDA 12.x
```

## Troubleshooting

**nvidia-smi: command not found**
- Driver install failed. Check: `dmesg | grep -i nvidia`
- Try: `sudo apt-get install --reinstall nvidia-driver-535`

**NVRM: GPU at PCIe address not found**
- Kernel module not loaded. Try: `sudo modprobe nvidia`
- Check secure boot is disabled: `mokutil --sb-state`

**Driver version mismatch with CUDA**
- See compatibility matrix: https://docs.nvidia.com/cuda/cuda-toolkit-release-notes/
