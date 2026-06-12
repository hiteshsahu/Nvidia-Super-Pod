# Runbook 01 — NVIDIA Driver Installation & Validation

## Overview

On AWS, drivers are installed automatically at first boot by the cloud-init script in `terraform/modules/gpu-node/templates/cloud-init.sh.tpl`. This runbook documents the steps for manual installation or for verifying a node that was provisioned outside of Terraform.

## Prerequisites

- Ubuntu 22.04 LTS
- AWS `g4dn.xlarge` (T4 GPU) or equivalent GPU instance
- Root or sudo access
- Secure Boot **disabled** (NVIDIA kernel modules cannot be signed by default)

---

## Steps

### 1. Verify the GPU is detected by the system

```bash
lspci | grep -i nvidia
# Expected: 00:1e.0 3D controller: NVIDIA Corporation TU104GL [Tesla T4] (rev a1)
```

If nothing appears the instance type does not have a physical GPU, or the PCI device is not passed through.

### 2. Check Secure Boot status

```bash
mokutil --sb-state
# Must return: SecureBoot disabled
```

If Secure Boot is enabled the NVIDIA kernel module will fail to load. Disable it in the instance firmware or use a pre-signed driver package.

### 3. Install kernel headers and build tools

```bash
sudo apt-get update -y
sudo apt-get install -y build-essential linux-headers-$(uname -r) dkms
```

### 4. Install the NVIDIA driver

```bash
sudo apt-get install -y nvidia-driver-535
```

> Driver 535 is the minimum for CUDA 12.x on Ubuntu 22.04. To pin a different version replace `535` with the desired major version (e.g. `550`).

### 5. Reboot

```bash
sudo reboot
```

### 6. Validate after reboot

```bash
# Driver version and GPU status
nvidia-smi
# Expected: table showing "Tesla T4", driver 535.x, CUDA 12.x

# Confirm driver version
nvidia-smi --query-gpu=driver_version --format=csv,noheader
# Expected: 535.x.x (must be >= 525 for CUDA 12.x)

# Confirm the kernel module loaded
lsmod | grep nvidia
# Expected: nvidia, nvidia_uvm, nvidia_drm, nvidia_modeset
```

### 7. Verify persistent mode (recommended for servers)

```bash
sudo nvidia-smi -pm 1
# Enabling persistence mode prevents driver cold-start latency between workloads.

nvidia-smi --query-gpu=persistence_mode --format=csv,noheader
# Expected: Enabled
```

---

## Troubleshooting

**`nvidia-smi: command not found`**
```bash
# Check if the package installed correctly
dpkg -l | grep nvidia-driver
# Reinstall if missing
sudo apt-get install --reinstall nvidia-driver-535
```

**`NVRM: GPU at PCI:0000:00:1e.0 not found`**
```bash
# Kernel module not loaded — try loading manually
sudo modprobe nvidia
# Check dmesg for errors
dmesg | grep -i nvidia
# Verify Secure Boot is off
mokutil --sb-state
```

**Driver/CUDA version mismatch**

Consult the [CUDA Compatibility Matrix](https://docs.nvidia.com/cuda/cuda-toolkit-release-notes/) — driver 535 supports up to CUDA 12.3.

**Module fails to build with DKMS**
```bash
# Rebuild manually
sudo dkms autoinstall
dmesg | tail -30
```
