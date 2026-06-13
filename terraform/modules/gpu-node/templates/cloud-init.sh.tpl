#!/bin/bash
# cloud-init — runs once on first boot
# Installs: NVIDIA drivers, CUDA, Docker, NVIDIA Container Toolkit, kubectl, Helm
set -euo pipefail
LOG="/var/log/superpod-init.log"
exec > >(tee -a $LOG) 2>&1

echo "======================================"
echo " NVIDIA SuperPod Node Bootstrap: ${node_name}"
echo " $(date)"
echo "======================================"

apt-get update -y && apt-get upgrade -y
apt-get install -y build-essential linux-headers-$(uname -r) dkms curl wget git \
  jq nvtop htop unzip software-properties-common apt-transport-https ca-certificates gnupg lsb-release

echo "[1/6] NVIDIA Driver ${driver_version}..."
apt-get install -y nvidia-driver-${driver_version}

echo "[2/6] CUDA Toolkit ${cuda_version}..."
wget -q https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb
dpkg -i cuda-keyring_1.1-1_all.deb
apt-get update -y && apt-get install -y cuda-toolkit-${cuda_version}
echo 'PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/local/cuda/bin' >> /etc/environment
echo 'LD_LIBRARY_PATH=/usr/local/cuda/lib64' >> /etc/environment

echo "[3/6] Docker + NVIDIA Container Toolkit..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
apt-get update -y && apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-ctk.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-ctk.gpg] https://#g' > /etc/apt/sources.list.d/nvidia-ctk.list
apt-get update -y && apt-get install -y nvidia-container-toolkit
nvidia-ctk runtime configure --runtime=docker
systemctl restart docker

echo "[4/6] kubectl ${k8s_version}..."
curl -fsSL https://pkgs.k8s.io/core:/stable:/v${k8s_version}/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/k8s.gpg
echo "deb [signed-by=/etc/apt/keyrings/k8s.gpg] https://pkgs.k8s.io/core:/stable:/v${k8s_version}/deb/ /" > /etc/apt/sources.list.d/kubernetes.list
apt-get update -y && apt-get install -y kubectl

echo "[5/6] Helm..."
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

echo "[6/6] CUDA validation samples..."
git clone --depth 1 https://github.com/NVIDIA/cuda-samples.git /opt/cuda-samples
cd /opt/cuda-samples/Samples/1_Utilities/deviceQuery && make
cd /opt/cuda-samples/Samples/1_Utilities/bandwidthTest && make

%{ if enable_dcgm }
echo "Installing DCGM..."
# cuda-keyring is already installed in step 2; use the existing CUDA repo
apt-get update -y && apt-get install -y datacenter-gpu-manager
systemctl enable nvidia-dcgm && systemctl start nvidia-dcgm
%{ endif }

echo "Waiting for data volume ${data_volume_device} to attach..."
timeout 120 bash -c "until [ -b ${data_volume_device} ]; do sleep 3; done" \
  || { echo "WARNING: ${data_volume_device} not found after 120s — skipping mount"; } \
  && {
    mkdir -p ${data_volume_mount}
    # Only format if the device has no filesystem yet (safe on reboot)
    blkid ${data_volume_device} || mkfs.ext4 -F ${data_volume_device}
    echo "${data_volume_device} ${data_volume_mount} ext4 defaults,nofail 0 2" >> /etc/fstab
    mount -a || true
  }

echo "======================================"
echo " Bootstrap complete — rebooting..."
echo "======================================"
reboot
