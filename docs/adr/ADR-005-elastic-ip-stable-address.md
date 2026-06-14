# ADR-005 — Elastic IP for stable addressing

**Status:** Accepted

---

## Context

The GPU node is a candidate for Spot purchasing to reduce cost. Spot instances can be interrupted by AWS with two minutes' notice and will receive a new public IP when relaunched. Service endpoints that use NodePort (Grafana :30300, Triton :30800) and SSH access are all addressed by the node's public IP.

Without a stable address, every Spot interruption requires updating kubeconfig server addresses, SSH `known_hosts`, curl commands in runbooks, and any external monitoring that polls the node. This friction makes Spot interruptions operationally expensive even when the node itself recovers quickly.

## Decision

Allocate one Elastic IP per GPU node and associate it with the instance. The association is managed by a separate `aws_eip_association` resource (not the deprecated `aws_eip.instance` attribute) so Terraform can replace the instance without destroying the EIP.

## Consequences

**Accepted trade-offs:**
- An unattached Elastic IP costs ~$3.60/month. If the cluster is torn down with `terraform destroy`, the EIP is released. If only the EC2 instance is stopped (not destroyed), the EIP remains attached at no charge — but if the instance is terminated without destroying the Terraform state, the EIP becomes unattached and incurs the fee until the next `terraform destroy`.
- One EIP per node does not scale to large clusters; a production deployment would use a load balancer or ingress controller with a single stable endpoint in front of a fleet.

**Benefits retained:**
- SSH command, kubeconfig server address, and NodePort service URLs remain stable across Spot interruptions and planned stop/start cycles.
- Runbook commands and Grafana bookmarks do not need updating after a node replacement.
- The EIP is tagged and tracked in Terraform state, so `terraform destroy` reliably releases it.
