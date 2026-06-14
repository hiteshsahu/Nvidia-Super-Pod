# ADR-001 — Single-node topology

**Status:** Accepted

---

## Context

The project goal is to exercise the full driver → Kubernetes → GPU Operator → observability stack in a way that mirrors an NVIDIA DGX SuperPod reference architecture. The question is whether to provision a multi-node cluster or a single node.

A multi-node setup would reflect production DGX SuperPod topology more accurately (dedicated control plane, multiple GPU workers). However, it multiplies cost, provisioning complexity, and the number of moving parts that can fail during an exploratory lab.

## Decision

Deploy a single `g4dn.xlarge` instance that acts as both the Kubernetes control plane and the only GPU worker node. The control-plane taint is removed so workloads can schedule on it.

## Consequences

**Accepted trade-offs:**
- No control-plane / worker separation — not representative of production HA topology.
- Single point of failure; a node failure terminates the entire cluster.
- Pod scheduling on the control plane requires the taint removal step in Ansible playbook 01, which would not exist in a production cluster.
- `nvidia.com/gpu.present=true` must be applied manually before the GPU Operator installs, because Node Feature Discovery cannot self-label until the operator is running — a deadlock that only exists on single-node clusters.

**Benefits retained:**
- All GPU Operator components (device plugin, GFD, DCGM, validator) are present and functional.
- The full observability pipeline (DCGM → Prometheus → Grafana) is exercised.
- Spot cost is ~$0.20/hr, making sustained lab use practical.
- Scaling to a real cluster is a variable change (`node_count`, add worker modules) — no architectural rework needed.
