# Runbook 04 — Observability: GPU Metrics with DCGM, Prometheus & Grafana

## Overview

The observability stack is deployed as a single `kube-prometheus-stack` Helm release (which bundles Prometheus + Grafana + Alertmanager) plus a separate DCGM Exporter release. DCGM Exporter exposes GPU hardware metrics; a `ServiceMonitor` CR tells Prometheus to scrape them automatically.

## Prerequisites

- GPU Operator running and GPU resource visible (see [Runbook 03](03-gpu-operator.md))
- `monitoring` namespace created: `kubectl apply -f kubernetes/base/namespaces.yaml`
- Helm 3.x installed

---

## DCGM Exporter

### 1. Install DCGM Exporter

```bash
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update

helm install dcgm-exporter nvidia/dcgm-exporter \
  --namespace monitoring \
  --version 3.3.5 \
  -f kubernetes/dcgm-exporter/values.yaml \
  --wait
```

### 2. Verify the exporter is running and scraping GPU metrics

```bash
kubectl get pods -n monitoring -l app.kubernetes.io/name=dcgm-exporter

# Port-forward and spot-check metrics
kubectl port-forward -n monitoring svc/dcgm-exporter 9400:9400 &
curl -s http://localhost:9400/metrics | grep -E 'DCGM_FI_DEV_(GPU_UTIL|GPU_TEMP|POWER_USAGE|FB_USED)'
# Expected: lines like DCGM_FI_DEV_GPU_UTIL{gpu="0",...} 0
kill %1
```

### 3. Key metrics collected

| Metric | Unit | Description |
|--------|------|-------------|
| `DCGM_FI_DEV_GPU_UTIL` | % | GPU SM utilization |
| `DCGM_FI_DEV_MEM_COPY_UTIL` | % | Memory copy engine utilization |
| `DCGM_FI_DEV_FB_USED` | MiB | Framebuffer memory used |
| `DCGM_FI_DEV_FB_FREE` | MiB | Framebuffer memory free |
| `DCGM_FI_DEV_GPU_TEMP` | °C | GPU die temperature |
| `DCGM_FI_DEV_POWER_USAGE` | W | Board power draw |
| `DCGM_FI_DEV_SM_CLOCK` | MHz | SM (compute) clock speed |
| `DCGM_FI_DEV_MEM_CLOCK` | MHz | Memory clock speed |
| `DCGM_FI_DEV_PCIE_TX_BYTES` | bytes | PCIe transmit bytes |
| `DCGM_FI_DEV_PCIE_RX_BYTES` | bytes | PCIe receive bytes |
| `DCGM_FI_DEV_ECC_SBE_VOL_TOTAL` | count | Single-bit ECC errors (volatile) |
| `DCGM_FI_DEV_ECC_DBE_VOL_TOTAL` | count | Double-bit ECC errors (volatile) |

---

## Prometheus + Grafana (kube-prometheus-stack)

### 1. Install kube-prometheus-stack

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --version 58.7.2 \
  -f kubernetes/monitoring/prometheus/values.yaml \
  --wait --timeout=10m
```

This installs: Prometheus, Grafana (NodePort 30300), node-exporter, kube-state-metrics, and Alertmanager (disabled by default).

### 2. Verify Prometheus targets include DCGM

```bash
# Port-forward Prometheus UI
kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090 &
# Open http://localhost:9090/targets
# dcgm-exporter ServiceMonitor target should show "UP"
kill %1
```

Or query via curl:

```bash
curl -s http://localhost:9090/api/v1/targets | \
  jq '.data.activeTargets[] | select(.labels.job | test("dcgm")) | {job:.labels.job, health:.health}'
```

### 3. Access Grafana

Grafana is exposed on NodePort **30300**:

```bash
# Get the node IP
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}')
echo "Grafana: http://${NODE_IP}:30300"
```

Default credentials:
- User: `admin`
- Password: `superpod-changeme` (set in `kubernetes/monitoring/prometheus/values.yaml`)

### 4. Import the GPU dashboard

The dashboard at `kubernetes/monitoring/grafana/dashboards/gpu-cluster.json` can be imported manually:

1. Grafana sidebar → **Dashboards** → **Import**
2. Upload `gpu-cluster.json` or paste its contents
3. Select the **Prometheus** data source
4. Click **Import**

Panels included: GPU utilization, VRAM used/free, temperature, power, SM/memory clocks, PCIe throughput, ECC errors.

### 5. Configure CloudWatch alarms (Terraform-managed)

The `gpu-node` Terraform module creates three CloudWatch alarms automatically:

| Alarm | Condition | Threshold |
|-------|-----------|-----------|
| `gpu-util-low` | GPU utilization < 10% for 15 min | Idle or stalled workload |
| `gpu-mem-high` | GPU memory > 90% for 2 min | OOM risk |
| `gpu-temp-high` | GPU temperature > 83°C for 2 min | Thermal throttle risk |

---

## GPU Health Thresholds (T4 / g4dn.xlarge)

| Metric | Normal | Warning | Critical |
|--------|--------|---------|----------|
| GPU Utilization | 50–100% during workload | < 10% during run | — |
| GPU Temperature | < 70°C | 70–83°C | > 83°C (throttle) |
| Power Draw | 30–70W | — | > 70W (T4 TDP) |
| VRAM Used | < 70% | 70–90% | > 90% (OOM risk) |
| ECC SBE errors | 0 | 1–10 | — |
| ECC DBE errors | 0 | > 0 | Hardware replacement |

> T4 TDP is **70W**. If you see sustained power draw above 70W, check for thermal throttling (`nvidia-smi -q -d CLOCK`).

---

## Prometheus Alert Rules

Save to `kubernetes/monitoring/prometheus/alerts.yaml` and apply with `kubectl apply -f`:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: gpu-alerts
  namespace: monitoring
  labels:
    release: prometheus
spec:
  groups:
    - name: gpu
      rules:
        - alert: GPUHighTemperature
          expr: DCGM_FI_DEV_GPU_TEMP > 83
          for: 2m
          labels:
            severity: warning
          annotations:
            summary: "GPU {{ $labels.gpu }} temperature {{ $value }}°C exceeds 83°C"

        - alert: GPUMemoryHigh
          expr: >
            100 * DCGM_FI_DEV_FB_USED /
            (DCGM_FI_DEV_FB_USED + DCGM_FI_DEV_FB_FREE) > 90
          for: 2m
          labels:
            severity: critical
          annotations:
            summary: "GPU {{ $labels.gpu }} VRAM usage {{ $value | printf \"%.0f\" }}% — OOM risk"

        - alert: GPUIdle
          expr: DCGM_FI_DEV_GPU_UTIL < 10
          for: 15m
          labels:
            severity: warning
          annotations:
            summary: "GPU {{ $labels.gpu }} utilization {{ $value }}% — idle or stalled"

        - alert: GPUECCDoubleBitError
          expr: DCGM_FI_DEV_ECC_DBE_VOL_TOTAL > 0
          for: 1m
          labels:
            severity: critical
          annotations:
            summary: "GPU {{ $labels.gpu }} double-bit ECC error — hardware issue"
```

---

## Troubleshooting

**No DCGM metrics in Prometheus**
```bash
# Check ServiceMonitor was picked up
kubectl get servicemonitor -n monitoring
kubectl describe servicemonitor dcgm-exporter -n monitoring

# Confirm the release label matches
kubectl get servicemonitor dcgm-exporter -n monitoring -o jsonpath='{.metadata.labels}'
# Must include: "release": "prometheus"
```

**Grafana "No Data" panels**
```bash
# Verify Prometheus data source is wired up
kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090 &
curl -s 'http://localhost:9090/api/v1/query?query=DCGM_FI_DEV_GPU_UTIL' | jq '.data.result | length'
# Should return > 0; if 0, exporter is not being scraped
```

**Grafana NodePort not reachable**
```bash
# Confirm the service and port
kubectl get svc -n monitoring prometheus-grafana
# Verify the node security group allows port 30300 inbound
```

**Prometheus OOM**
```bash
# Reduce retention in kubernetes/monitoring/prometheus/values.yaml
# retention: 7d
# retentionSize: 5GB
helm upgrade prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring -f kubernetes/monitoring/prometheus/values.yaml
```
