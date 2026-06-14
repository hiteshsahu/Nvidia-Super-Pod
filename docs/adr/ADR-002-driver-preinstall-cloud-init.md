# ADR-002 — Driver pre-install via cloud-init

**Status:** Accepted

---

## Context

The NVIDIA GPU Operator can manage the full driver lifecycle — downloading, compiling via DKMS, and loading the kernel module. This is its default mode and is appropriate when provisioning nodes that have no prior GPU setup.

However, the GPU Operator's driver installer runs as a pod inside Kubernetes. This creates a bootstrap dependency: the driver must be present before `containerd` can expose GPU devices to containers, but the driver installer is itself a container that requires a functioning GPU-capable runtime to schedule.

On a fresh node the circular dependency resolves because the operator installs the driver at the host level before enabling the runtime. In practice the resolution is fragile: it depends on the operator's DaemonSet scheduling before any other GPU pod, and a version mismatch between the operator's bundled driver and the host OS kernel headers causes a DKMS build failure that stalls the entire operator indefinitely with no clear error.

A secondary concern is Secure Boot: signed driver modules from the Ubuntu apt repository pass Secure Boot validation out of the box; DKMS-compiled modules require manual key enrollment.

## Decision

Install NVIDIA driver 535, CUDA Toolkit 12-3, Docker, and the NVIDIA Container Toolkit via `cloud-init.sh.tpl` on first boot, before Kubernetes is bootstrapped. Set `driver.enabled: false` in the GPU Operator Helm values so the operator does not attempt a second install.

## Consequences

**Accepted trade-offs:**
- Driver version is pinned in `cloud-init.sh.tpl` and must be updated manually to change (versus the operator managing upgrades automatically).
- Driver upgrades require Ansible playbook 04 (`04-upgrade-driver.yml`) to cordon, drain, reinstall, and uncordon the node — a day-2 operation not needed when the operator manages the lifecycle.
- The operator's driver validation pod runs but has nothing to install, which is slightly misleading in the operator logs.

**Benefits retained:**
- No DKMS compilation on first boot; the Ubuntu apt driver package includes pre-built kernel modules for the 22.04 HWE kernel.
- Secure Boot compatibility without key enrollment.
- Kubernetes bootstrap (Ansible playbook 01) starts with a node that already has a working `nvidia-smi`, making the kubeadm init sequence deterministic.
- The GPU Operator still manages device plugin, GFD, DCGM, and validator — only driver management is opted out.
