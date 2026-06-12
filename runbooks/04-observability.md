# Runbook 04 — Observability: Monitoring GPU Metrics

## Overview
This runbook covers setup of Prometheus, Grafana, and NVIDIA DCGM exporter for comprehensive GPU cluster monitoring.

## Prerequisites
- Kubernetes cluster with GPU Operator running
- kubectl configured
- Helm 3.x installed
- 2-4GB storage for Prometheus and Grafana

## DCGM Exporter Setup

### 1. Install DCGM Exporter via Helm
```bash
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update

helm install dcgm-exporter nvidia/dcgm-exporter \
  --namespace gpu-operator \
  -f kubernetes/dcgm-exporter/values.yaml \
  --wait
```

### 2. Verify exporter is running
```bash
kubectl get pods -n gpu-operator | grep dcgm
kubectl port-forward -n gpu-operator svc/dcgm-exporter 9400:9400 &
curl http://localhost:9400/metrics | head -20
```

### 3. Check available metrics
```bash
curl http://localhost:9400/metrics | grep DCGM_FI_DEV
# Should see metrics like:
# DCGM_FI_DEV_GPU_UTIL
# DCGM_FI_DEV_GPU_TEMP
# DCGM_FI_DEV_POWER_USAGE
# DCGM_FI_DEV_CLOCK_SM
```

## Prometheus Setup

### 1. Install Prometheus
```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install prometheus prometheus-community/prometheus \
  --namespace monitoring \
  --create-namespace \
  -f kubernetes/monitoring/prometheus/values.yaml \
  --wait
```

### 2. Configure scrape configs for GPU metrics
Add to prometheus values.yaml:
```yaml
prometheus:
  prometheusSpec:
    serviceMonitorSelectorNilUsesHelmValues: false
    additionalScrapeConfigs:
      - job_name: 'dcgm-exporter'
        kubernetes_sd_configs:
          - role: pod
            namespaces:
              names:
                - gpu-operator
        relabel_configs:
          - source_labels: [__meta_kubernetes_pod_label_app]
            action: keep
            regex: dcgm-exporter
          - source_labels: [__address__]
            action: replace
            regex: ([^:]+)(?::\d+)?
            replacement: ${1}:9400
            target_label: __address__
```

### 3. Verify Prometheus targets
```bash
kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090 &
# Open http://localhost:9090/targets
# All DCGM targets should show "UP"
```

## Grafana Setup

### 1. Install Grafana
```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm install grafana grafana/grafana \
  --namespace monitoring \
  -f kubernetes/monitoring/grafana/values.yaml \
  --wait
```

### 2. Get Grafana credentials
```bash
kubectl get secret -n monitoring grafana -o jsonpath="{.data.admin-password}" | base64 --decode
# Default user: admin
```

### 3. Access Grafana
```bash
kubectl port-forward -n monitoring svc/grafana 3000:80 &
# Open http://localhost:3000
```

### 4. Add Prometheus data source
- URL: `http://prometheus-operated.monitoring:9090`
- Access: Browser
- Save & Test

### 5. Import GPU dashboard
- Import from `kubernetes/monitoring/grafana/dashboards/gpu-cluster.json`
- Visualize GPU utilization, temperature, power, memory across cluster

## Key Metrics to Monitor

| Metric | Threshold | Action |
|--------|-----------|--------|
| GPU Utilization | < 50% | Check job scheduling |
| GPU Temperature | > 80°C | Thermal throttling likely |
| Power Draw | > 250W (T4) | Check TDP limits |
| Memory Used | > 90% | OOM risk, prevent new workloads |
| XID Errors | > 0 | Investigate hardware issues |
| ECC Errors | Increasing | Plan node maintenance |

## Alerts Configuration

Create alert rules in `kubernetes/monitoring/prometheus/alerts.yaml`:

```yaml
groups:
  - name: gpu_alerts
    rules:
      - alert: GPUHighTemperature
        expr: DCGM_FI_DEV_GPU_TEMP > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "GPU high temperature"

      - alert: GPUMemoryHigh
        expr: (DCGM_FI_DEV_FB_USED / DCGM_FI_DEV_FB_FREE) > 0.9
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "GPU memory > 90%"

      - alert: XIDErrorDetected
        expr: DCGM_FI_DEV_XID_ERRORS > 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "XID error detected on GPU"
```

## Troubleshooting

**No DCGM metrics appearing in Prometheus**
- Check exporter pod: `kubectl logs -n gpu-operator -l app=dcgm-exporter`
- Check scrape config: `kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090` then check targets
- Verify network connectivity between Prometheus and exporter pods

**Grafana dashboard shows "No Data"**
- Verify data source is connected: Settings > Data Sources
- Check metric names in dashboard JSON match Prometheus output
- Ensure sufficient time range is selected

**Memory usage for Prometheus too high**
- Reduce retention period in values.yaml: `retention: 7d`
- Implement metric relabeling to drop non-essential metrics
- Add PVC for persistent storage

## Next Steps
- Set up PagerDuty or Slack integration for alerts
- Configure backup of Prometheus data
- Create runbooks for common alert responses
