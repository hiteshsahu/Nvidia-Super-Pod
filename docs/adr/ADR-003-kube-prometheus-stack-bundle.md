# ADR-003 — kube-prometheus-stack bundle

**Status:** Accepted

---

## Context

The observability stack requires Prometheus (metrics store), Grafana (dashboards), Alertmanager (alert routing), node-exporter (host metrics), and kube-state-metrics (cluster resource metrics). These components can be installed as separate Helm releases or bundled.

Installing them separately allows independent version pinning and smaller blast radius per upgrade. It also requires manually wiring ServiceMonitors, RBAC, and Grafana data sources between releases — config that the bundle pre-wires by default.

A specific complication with separate installs: Prometheus only scrapes ServiceMonitors whose namespace matches its own `serviceMonitorNamespaceSelector`, and whose labels match its `serviceMonitorSelector`. Without the bundle's default of `serviceMonitorSelectorNilUsesHelmValues: false`, Prometheus silently ignores every ServiceMonitor outside its own namespace — including the DCGM Exporter's ServiceMonitor in the `monitoring` namespace when Prometheus is also in `monitoring` but installed under a different release.

## Decision

Use `prometheus-community/kube-prometheus-stack` (version 58.7.2) as a single Helm release. Set `serviceMonitorSelectorNilUsesHelmValues: false` and `serviceMonitorSelector: {}` so Prometheus scrapes all ServiceMonitors cluster-wide regardless of label or namespace.

## Consequences

**Accepted trade-offs:**
- A single Helm release controls the versions of five components; upgrading one (e.g. Grafana) requires upgrading the chart, which may bump others.
- The chart is large — `helm install` pulls and renders hundreds of templates; initial install takes 8–10 minutes.
- `serviceMonitorSelector: {}` is broad — any ServiceMonitor in any namespace is scraped. In a multi-tenant cluster this would need tightening.

**Benefits retained:**
- Grafana data source for Prometheus is pre-configured.
- RBAC for Prometheus to read ServiceMonitors cluster-wide is pre-configured.
- Alertmanager is available with no extra wiring.
- node-exporter and kube-state-metrics are included, giving host and cluster metrics without additional releases.
- DCGM Exporter ServiceMonitor is automatically discovered without label tricks — verified by the `release: prometheus` label that the Helm chart adds automatically to its own ServiceMonitor selector when `serviceMonitorSelectorNilUsesHelmValues: false`.
