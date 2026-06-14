# ADR-004 — EBS gp3 volumes

**Status:** Accepted

---

## Context

The GPU node requires two EBS volumes: a root volume (OS, drivers, Docker image layers) and a data volume (model checkpoints, datasets at `/mnt/data`). AWS offers gp2 and gp3 as the general-purpose SSD tiers in this region.

gp2 performance scales with volume size: 100 IOPS/GiB baseline, capped at 16,000 IOPS. A 100 GiB gp2 root volume delivers 300 IOPS at baseline. Model loading and Docker layer extraction are I/O-intensive; 300 IOPS creates a visible bottleneck when pulling multi-gigabyte container images or loading large checkpoints.

gp3 decouples performance from size: 3,000 IOPS and 125 MB/s are the baseline for any volume, regardless of size, at the same price per GiB as gp2. Additional IOPS and throughput can be purchased independently up to 16,000 IOPS and 1,000 MB/s.

Both tiers support encryption at rest using AWS-managed KMS keys.

## Decision

Use `gp3` for both volumes with encryption enabled:
- Root: 100 GiB gp3 — OS, kernel headers, NVIDIA driver, Docker images
- Data: 200 GiB gp3 — model repository at `/mnt/data`, training datasets, CUDA samples

No additional IOPS or throughput are purchased beyond the 3,000 IOPS / 125 MB/s baseline, which is sufficient for the T4's PCIe Gen3 ×16 bandwidth ceiling.

## Consequences

**Accepted trade-offs:**
- gp3 throughput baseline (125 MB/s) is below the T4's PCIe bandwidth (~15 GB/s); storage is the bottleneck for large sequential reads. Purchasing additional throughput or switching to io2 would be needed for production-scale data pipelines.
- The data volume is formatted on first boot by cloud-init. A `blkid` check prevents reformatting on restart, but the volume's lifecycle is tied to the EC2 instance — `terraform destroy` deletes it.

**Benefits retained:**
- 10× IOPS improvement over an equivalently sized gp2 volume at no extra cost.
- Encryption at rest is enabled by default; no key management overhead for a lab.
- `terraform destroy` cleanly removes both volumes with no manual cleanup needed.
