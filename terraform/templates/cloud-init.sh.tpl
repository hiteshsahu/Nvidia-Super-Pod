#!/bin/bash
# cloud-init bootstrap script — runs once on first boot
# Installs: NVIDIA drivers, CUDA toolkit, Docker, kubectl, Helm
set -euo pipefail

LOG="/var/log/superpod-init.log"
exec > >(tee -a $LOG) 2>&1

echo "======================================"
echo " NVIDIA SuperPod — Node Bootstrap"
echo " $(date)"
echo "======================================"

# ── System update ──────────────────────────────────────────────
apt-get update -y
apt-get upgrade -y
apt-get install -y \
  build-essential \
  linux-headers-$(uname -r) \
  dkms \
  curl \
  wget \
  git \
  jq \
  nvtop \
  htop \
  unzip \
  software-properties-common \
  apt-transport-https \
  ca-certificates \
  gnupg \
  lsb-release

# ── NVIDIA Driver ──────────────────────────────────────────────
echo "[1/6] Installing NVIDIA driver ${driver_version}..."
apt-get install -y nvidia-driver-${driver_version}

# ── CUDA Toolkit ───────────────────────────────────────────────
echo "[2/6] Installing CUDA ${cuda_version}..."
wget -q https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb
dpkg -i cuda-keyring_1.1-1_all.deb
apt-get update -y
apt-get install -y cuda-toolkit-${cuda_version}

# Add CUDA to PATH
echo 'export PATH=/usr/local/cuda/bin:$PATH' >> /etc/environment
echo 'export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH' >> /etc/environment
export PATH=/usr/local/cuda/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH

# ── Docker ─────────────────────────────────────────────────────
echo "[3/6] Installing Docker..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  > /etc/apt/sources.list.d/docker.list
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# NVIDIA Container Toolkit — allows Docker to use GPU
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
  gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
  > /etc/apt/sources.list.d/nvidia-container-toolkit.list
apt-get update -y
apt-get install -y nvidia-container-toolkit
nvidia-ctk runtime configure --runtime=docker
systemctl restart docker

# ── kubectl ────────────────────────────────────────────────────
echo "[4/6] Installing kubectl ${k8s_version}..."
curl -fsSL https://pkgs.k8s.io/core:/stable:/v${k8s_version}/deb/Release.key | \
  gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
  https://pkgs.k8s.io/core:/stable:/v${k8s_version}/deb/ /" \
  > /etc/apt/sources.list.d/kubernetes.list
apt-get update -y
apt-get install -y kubectl

# ── Helm ───────────────────────────────────────────────────────
echo "[5/6] Installing Helm..."
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# ── CUDA Samples (for validation) ─────────────────────────────
echo "[6/6] Installing CUDA samples for validation..."
git clone --depth 1 https://github.com/NVIDIA/cuda-samples.git /opt/cuda-samples
cd /opt/cuda-samples/Samples/1_Utilities/deviceQuery && make
cd /opt/cuda-samples/Samples/1_Utilities/bandwidthTest && make

# ── Reboot to load NVIDIA kernel module ───────────────────────
echo "======================================"
echo " Bootstrap complete — rebooting now"
echo " Check $LOG for full output"
echo "======================================"
reboot
