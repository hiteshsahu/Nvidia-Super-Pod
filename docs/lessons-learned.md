# Lessons Learned — NVIDIA SuperPod Lab

Operational insights gathered while building and running this stack.

---

## Driver & CUDA

**`cuda-keyring` version matters**

Using `cuda-keyring_1.0-1_all.deb` and later upgrading to `1.1-1_all.deb` in a second apt step causes a `dpkg` conflict that silently aborts the DCGM install. Always use `1.1-1` for Ubuntu 22.04 and only install it once. The DCGM section of cloud-init was initially re-installing the keyring at a different version — this was fixed by removing the redundant install step and relying on the repo already registered in step 2.

**Driver must be installed before the kernel modules are referenced**

If you install `nvidia-driver-535` without `linux-headers-$(uname -r)` already present, DKMS silently skips module compilation. The module exists on disk but cannot be loaded, so `nvidia-smi` returns "No devices were found." Always install headers first.

**Secure Boot blocks unsigned kernel modules**

`nvidia-smi: command not found` after a reboot on a node with Secure Boot enabled is a red herring — the driver installs fine, but the kernel module fails to load because it is not signed by a key trusted by the firmware. Check `mokutil --sb-state` before debugging anything else.

---

## Terraform & Cloud-Init

**EBS volume attachment is asynchronous**

The EBS data volume is attached after the instance is running and cloud-init has already started executing. The original cloud-init ran `mkfs.ext4 /dev/sdf` immediately on boot — on a fast machine this raced the attachment and failed silently (`2>/dev/null || true`). The fix was a `timeout 120 bash -c "until [ -b /dev/sdf ]; do sleep 3; done"` poll before formatting.

**`blkid` before `mkfs` prevents accidental reformats**

On instance restart (e.g. after a Spot interruption) the data volume is reattached. Without a filesystem check, the original script would reformat the volume and destroy all data. `blkid /dev/sdf || mkfs.ext4 -F /dev/sdf` formats only if no filesystem signature is found.

**Deprecated `instance =` on `aws_eip`**

The AWS Terraform provider v5 deprecated the `instance` argument on `aws_eip`. Using it alongside other lifecycle hooks (like `aws_volume_attachment`) causes implicit dependency ordering issues. Replacing it with a standalone `aws_eip_association` resource makes the dependency graph explicit and eliminates the deprecation warning.

**Provider `default_tags` vs explicit module tags**

The `provider` block's `default_tags` applies tags to every resource in the account region automatically. Passing the same tag map explicitly to modules and using `merge(var.tags, {...})` results in duplicate tag keys — AWS deduplicates them with the explicit value winning, but it creates unnecessary noise. Keep `default_tags` for the common keys and pass only resource-specific tags (like `Name`) to modules.

---

## Kubernetes & GPU Operator

**Driver pre-install breaks the default GPU Operator flow**

The GPU Operator assumes it manages the full lifecycle: it installs the driver, toolkit, and plugin in sequence. If the driver is already installed when the operator starts, the operator's driver DaemonSet tries to install again and fails on a version check. Setting `driver.enabled: false` is the correct solution — document this explicitly or your operator will be stuck in `Init` forever.

**Single-node clusters need the GPU label applied manually**

Node Feature Discovery labels the node with `nvidia.com/gpu.present=true` only after the operator is running. On a fresh single-node cluster, the operator's admission webhook blocks pod scheduling until the label exists — a deadlock. The fix is to label the node manually before installing the operator.

**`serviceMonitorSelectorNilUsesHelmValues: false` is not default**

By default, kube-prometheus-stack only scrapes ServiceMonitors in the same namespace as the Prometheus release, or those matching a specific label selector. Without setting `serviceMonitorSelectorNilUsesHelmValues: false` and clearing `serviceMonitorSelector`, the DCGM Exporter ServiceMonitor in `monitoring` is silently ignored. This caused an hour of "why are there no GPU metrics?" debugging.

**DCGM Exporter namespace must match its ServiceMonitor's `release` label**

The Prometheus Operator discovers ServiceMonitors by matching the `release: prometheus` label (the Helm release name of kube-prometheus-stack). If the ServiceMonitor's label value doesn't match exactly, it is never picked up. When debugging missing metrics, always check `kubectl get servicemonitor -A` and compare labels.

---

## Observability

**T4 TDP is 70W, not 250W**

The T4 has a 70W TDP. Any alert threshold set above 70W for power draw will never fire. P3/P4d instances (V100/A100) have higher TDPs (300W+). Always look up the spec for the specific GPU rather than copying thresholds from a different instance family.

**ECC errors are a leading indicator, not a lagging one**

Single-bit ECC errors (SBE) are corrected in hardware and don't cause job failures. But a rising SBE count over days is a reliable early warning of DRAM degradation before it escalates to uncorrectable double-bit errors (DBE) and job crashes. Set a Prometheus alert on `rate(DCGM_FI_DEV_ECC_SBE_VOL_TOTAL[1h]) > 0` to catch this early.

**GPU utilization below 10% during a training job almost always means data loading is the bottleneck**

If `DCGM_FI_DEV_GPU_UTIL` is low but the job is running, the GPU is waiting for data. Increasing DataLoader workers, using pinned memory, or pre-loading data to `/dev/shm` typically brings utilization back above 80%.

---

## Windows Deployment (WSL2)

**Ansible must be installed via pip, not apt**

`sudo apt install ansible` on Ubuntu 22.04 gives version 2.10.8, which is too old — the remote tmp directory command uses backtick syntax that fails with exit code 127. Install via `pip3 install --user ansible` to get 2.17+ and add `~/.local/bin` to PATH.

**Windows SSH keys have 0777 permissions in WSL2**

SSH keys generated on Windows and accessed via `/mnt/c/Users/...` in WSL2 have world-readable permissions (0777). SSH rejects these with "UNPROTECTED PRIVATE KEY FILE". Always copy the key into WSL2 and `chmod 600` it: `cp /mnt/c/Users/<user>/.ssh/id_rsa ~/.ssh/id_rsa_superpod && chmod 600 ~/.ssh/id_rsa_superpod`.

**EBS data volume attaches as `nvme1n1`, not `/dev/sdf`**

On Nitro-based EC2 instances (all modern instance types including t3, g4dn), EBS volumes attach as NVMe devices (`/dev/nvme1n1`) regardless of the device name specified in Terraform (`/dev/xvdf` or `/dev/sdf`). The cloud-init template originally waited for `/dev/sdf` which never appeared. Fix: use `/dev/nvme1n1` in the cloud-init template.

**`/etc/environment` does not support shell variable expansion**

cloud-init appended `export PATH=/usr/local/cuda/bin:$PATH` to `/etc/environment`. Unlike `.bashrc`, `/etc/environment` is parsed by PAM — it does not expand `$PATH`. The result was a literal PATH of `/usr/local/cuda/bin:$PATH` which broke every command in non-interactive SSH sessions (including all Ansible tasks). Fix: write the full absolute PATH without variable references.

**containerd ships with a disabled CRI plugin by default on Ubuntu**

The default `/etc/containerd/config.toml` installed by apt has the CRI plugin disabled (`disabled_plugins = ["cri"]`). kubeadm's preflight check catches this and aborts. Fix before running kubeadm: `sudo rm /etc/containerd/config.toml && sudo containerd config default | sudo tee /etc/containerd/config.toml && sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml && sudo systemctl restart containerd`.

**`br_netfilter` kernel module must be loaded before kubeadm init**

kubeadm requires `/proc/sys/net/bridge/bridge-nf-call-iptables` to exist. This file is only present when the `br_netfilter` kernel module is loaded. On a fresh Ubuntu 22.04 node it is not loaded by default. Load it with `sudo modprobe br_netfilter` and persist it via `/etc/modules-load.d/br_netfilter.conf`.

**Ansible `playbook_dir` resolves to the local controller path, not the remote node**

When Ansible runs `kubectl apply -f {{ playbook_dir }}/../../kubernetes/...`, `playbook_dir` expands to the path on the controller machine (e.g. `/mnt/e/WorkSpace/...`). kubectl runs on the remote node where that path doesn't exist. Fix: use the `copy` module to sync manifests to the remote node first, then reference the remote path (e.g. `/home/ubuntu/kubernetes/`).

**DCGM Exporter moved out of the NVIDIA Helm repo**

The `nvidia/dcgm-exporter` chart no longer exists in `https://helm.ngc.nvidia.com/nvidia`. It moved to a dedicated repo. Add: `helm repo add gpu-helm-charts https://nvidia.github.io/dcgm-exporter/helm-charts`. Latest version as of 2026-06: `4.8.2`.

**New AWS accounts have 0 GPU vCPU quota**

New AWS accounts cannot launch GPU instances (`g4dn`, `p3`, `p4d`) until a service quota increase is approved for "Running On-Demand G and VT instances". Request at least 4 vCPUs. AWS may reject the first request — resubmit with a detailed use case. Use `t3.medium` in the meantime to validate the full Terraform + Ansible + Kubernetes pipeline end to end.

**CloudWatch log group persists after `terraform destroy`**

The VPC flow logs CloudWatch log group (`/aws/vpc/superpod-flow-logs`) is not destroyed by `terraform destroy` when the state is lost or partially applied. On the next `terraform apply` it fails with `ResourceAlreadyExistsException`. Fix: `terraform import module.vpc.aws_cloudwatch_log_group.flow_logs[0] /aws/vpc/superpod-flow-logs` then re-apply.

---

## Cost

**Spot interruptions are infrequent but must be handled**

`g4dn.xlarge` in `eu-central-1` has < 5% interruption frequency. Using `instance_interruption_behavior: terminate` combined with an Elastic IP and durable EBS volumes means the node comes back cleanly after a new Spot instance is allocated — the only downside is the minutes of downtime. Checkpointing training jobs every few steps (`torch.save` to `/mnt/data`) limits the cost of an interruption to < 1 epoch.

**NAT Gateways are the largest surprise cost**

Two NAT Gateways (for HA) each cost ~$32/month at baseline plus $0.045/GB data processed. In a lab that pulls large container images repeatedly, data charges add up fast. Pull images once, push to ECR, and reference ECR from Kubernetes manifests to minimize NAT egress.
