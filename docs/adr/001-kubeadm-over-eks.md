# ADR-001: Use kubeadm on EC2 instead of EKS

**Status:** Accepted  
**Date:** 2026-06-13

## Context

The project provisions a single GPU node on AWS to run Kubernetes-orchestrated GPU workloads (GPU Operator, DCGM Exporter, PyTorch, Triton). A Kubernetes cluster is required. Two options were evaluated: Amazon EKS and self-managed kubeadm on EC2.

## Decision

Use kubeadm bootstrapped via Ansible on a single EC2 instance. Do not use EKS.

| Item              | EKS	                                     | kubeadm (this project)   |
|-------------------|------------------------------------------|--------------------------|
| Cost	             | +$0.10/hr control plane fee (~$72/month) | 	$0                      |
| Setup time	       | ~15 min (but more moving parts)	         | ~5 min via Ansible       |
| GPU Operator	     | Works, but needs node group config       | 	Works out of the box    |
| DCGM / Prometheus | 	Needs IAM roles for service accounts    | 	Simple Helm install     |
| SSH into node	    | Harder (managed nodes)                   | 	Direct ssh ubuntu@<ip>  |
| Teardown	         | Multiple resources to destroy	           | Single terraform destroy |

## Reasons

**Cost**  
EKS charges $0.10/hr for the managed control plane (~$72/month) regardless of workload. For a lab running spot sessions of ~30 minutes, this adds disproportionate fixed cost on top of the instance fee.

**Complexity vs. benefit**  
EKS manages the control plane, but all GPU work runs on worker nodes. A single-node lab never benefits from a managed control plane — there is nothing to manage. kubeadm gives identical Kubernetes API surface with zero overhead.

**SSH and debugging access**  
kubeadm on EC2 allows direct `ssh ubuntu@<node-ip>` and `nvidia-smi` on the host. EKS managed nodes make this harder and discourage it by design.

**Teardown simplicity**  
`terraform destroy` removes everything in one command. EKS teardown involves the cluster, node groups, IAM roles for service accounts, and the control plane — more surface area for orphaned resources and lingering AWS charges.

**GPU Operator compatibility**  
The NVIDIA GPU Operator works on both, but requires no extra IAM configuration (IRSA) on a self-managed node. On EKS, DCGM ServiceMonitors and Prometheus require additional IAM roles for service accounts to function correctly.

## Trade-offs

| Concern | Impact |
|---|---|
| No managed control plane HA | Acceptable — single-node lab, not production |
| Manual kubeadm upgrades | Acceptable — upgrade playbook (`04-upgrade-driver.yml`) already exists |
| No auto-scaling node groups | Acceptable — scale up by changing `instance_type` in `terraform.tfvars` |

## When to revisit

Switch to EKS if the project expands to:
- Multiple GPU worker nodes requiring auto-scaling
- Multi-team access with fine-grained RBAC
- Production inference workloads requiring managed upgrades and HA
