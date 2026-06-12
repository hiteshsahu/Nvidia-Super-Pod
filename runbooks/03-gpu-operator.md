# Runbook 03 — NVIDIA GPU Operator on Kubernetes

## Prerequisites
- Kubernetes cluster running (kubeadm, EKS, or kind)
- Helm 3.x installed
- Node with NVIDIA GPU

## Steps

### 1. Add NVIDIA Helm repository
```bash
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update
```

### 2. Install GPU Operator
```bash
helm install gpu-operator nvidia/gpu-operator \
  --namespace gpu-operator \
  --create-namespace \
  -f kubernetes/gpu-operator/values.yaml \
  --wait --timeout=10m
```

### 3. Verify all operator pods are running
```bash
kubectl get pods -n gpu-operator
# All pods should be Running or Completed
```

### 4. Verify GPU resource is visible
```bash
kubectl get nodes -o json | \
  jq '.items[].status.allocatable | select(."nvidia.com/gpu")'
# Expected: "nvidia.com/gpu": "1"
```

### 5. Run validation workload
```bash
kubectl apply -f kubernetes/workloads/cuda-test.yaml
kubectl wait --for=condition=complete job/cuda-vector-add --timeout=5m
kubectl logs job/cuda-vector-add
```

## Troubleshooting

**Pods stuck in Init state**
- Check NFD (Node Feature Discovery) labels: `kubectl get nodes --show-labels | grep nvidia`
- Force label: `kubectl label node <node> nvidia.com/gpu.present=true`

**GPU not visible in allocatable resources**
- Check device plugin: `kubectl get pods -n gpu-operator | grep device-plugin`
- Restart: `kubectl rollout restart daemonset/gpu-operator-node-feature-discovery-worker -n gpu-operator`
