# Runbook 03 — NVIDIA GPU Operator on Kubernetes

## Overview

The GPU Operator automates everything the Kubernetes scheduler needs to schedule GPU workloads: device plugin, node feature discovery, and runtime configuration. Because drivers and the container toolkit are pre-installed by cloud-init, the operator is configured with `driver.enabled: false` — it manages everything else.

## Prerequisites

- Kubernetes cluster running (kubeadm single-node or EKS)
- NVIDIA driver 535 and CUDA 12-3 installed and validated
- Helm 3.x installed: `helm version`
- `kubectl` configured and pointing at the cluster

---

## Steps

### 1. Create namespaces

```bash
kubectl apply -f kubernetes/base/namespaces.yaml
# Creates: gpu-operator, monitoring, inference, training
```

### 2. Label the GPU node

The GPU Operator's webhook targets nodes with `nvidia.com/gpu.present=true`. On a single-node cluster you must label the node manually before installing:

```bash
NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
kubectl label node "$NODE" nvidia.com/gpu.present=true
```

Node Feature Discovery (installed with the operator) will manage this label automatically on multi-node clusters.

### 3. Add the NVIDIA Helm repository

```bash
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update
```

### 4. Install the GPU Operator

```bash
helm install gpu-operator nvidia/gpu-operator \
  --namespace gpu-operator \
  --version v24.3.0 \
  -f kubernetes/gpu-operator/values.yaml \
  --wait --timeout=10m
```

### 5. Verify all operator pods are running

```bash
kubectl get pods -n gpu-operator
# All pods should reach Running or Completed within ~5 minutes.
# Expected pods:
#   gpu-operator-*                    (operator controller)
#   nvidia-device-plugin-daemonset-*  (exposes nvidia.com/gpu resource)
#   nvidia-dcgm-*                     (DCGM daemon)
#   nvidia-container-toolkit-daemonset-* (container runtime config)
#   gpu-feature-discovery-*           (GFD node labels)
#   nvidia-node-status-exporter-*
#   nvidia-operator-validator-*       (validation pod — Completed is fine)
```

### 6. Verify the GPU resource is visible to the scheduler

```bash
kubectl get nodes -o json | \
  jq '.items[].status.allocatable | select(."nvidia.com/gpu")'
# Expected: { "nvidia.com/gpu": "1" }
```

### 7. Check GPU Feature Discovery labels

```bash
kubectl get node -o json | jq '.items[].metadata.labels | with_entries(select(.key | startswith("nvidia")))'
# Expected labels include:
#   nvidia.com/gpu.present: "true"
#   nvidia.com/gpu.product: "Tesla-T4"
#   nvidia.com/cuda.driver.major: "535"
```

### 8. Run the CUDA validation job

```bash
kubectl apply -f kubernetes/workloads/cuda-test.yaml
kubectl wait --for=condition=complete job/cuda-validation -n training --timeout=5m
kubectl logs -n training job/cuda-validation
# Expected last line: All GPU validation checks PASSED.

# Cleanup
kubectl delete job cuda-validation -n training
```

---

## Troubleshooting

**Pods stuck in `Init:0/1` or `Pending`**
```bash
# Check if the node has the GPU label
kubectl get nodes --show-labels | grep nvidia

# Apply the label manually if missing
NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
kubectl label node "$NODE" nvidia.com/gpu.present=true --overwrite

# Check operator events
kubectl describe pod -n gpu-operator -l app=gpu-operator
```

**`nvidia.com/gpu` not in allocatable resources**
```bash
# Check device plugin logs
kubectl logs -n gpu-operator -l app=nvidia-device-plugin-daemonset

# Restart the device plugin
kubectl rollout restart daemonset/nvidia-device-plugin-daemonset -n gpu-operator
kubectl rollout status daemonset/nvidia-device-plugin-daemonset -n gpu-operator
```

**Validator pod fails**
```bash
kubectl logs -n gpu-operator -l app=nvidia-operator-validator
# Common cause: runtime class not configured.
# Check containerd config:
cat /etc/containerd/config.toml | grep nvidia
```

**Container toolkit not configuring the runtime**
```bash
kubectl logs -n gpu-operator -l app=nvidia-container-toolkit-daemonset
# If the docker socket path differs, update toolkit.env in gpu-operator/values.yaml
```
