# Copyright 2026 Hitesh Kumar Sahu — https://hiteshsahu.com
# SPDX-License-Identifier: Apache-2.0

import os
import sys
import time
import torch
import torchvision.models as models

if not torch.cuda.is_available():
    print("ERROR: no GPU visible to PyTorch", file=sys.stderr)
    sys.exit(1)

device = torch.device("cuda")
props  = torch.cuda.get_device_properties(0)

print(f"GPU      : {props.name}")
print(f"VRAM     : {props.total_memory / 1e9:.1f} GB")
print(f"SMs      : {props.multi_processor_count}")
print(f"PyTorch  : {torch.__version__}")
print(f"CUDA     : {torch.version.cuda}")
print()

# BATCH_SIZE env var lets you tune without editing this file:
#   64  — default, suits T4 16 GB (AWS g4dn.xlarge)
#   32  — recommended for GTX 4060 8 GB (local Windows/WSL2)
BATCH        = int(os.environ.get("BATCH_SIZE", 64))
WARMUP_STEPS = int(os.environ.get("WARMUP_STEPS", 5))
TIMED_STEPS  = int(os.environ.get("TIMED_STEPS", 50))

print(f"Batch size   : {BATCH}")
print(f"Warmup steps : {WARMUP_STEPS}")
print(f"Timed steps  : {TIMED_STEPS}")
print()

model     = models.resnet50().to(device)
optimizer = torch.optim.SGD(model.parameters(), lr=0.01, momentum=0.9)
criterion = torch.nn.CrossEntropyLoss()

dummy_x = torch.randn(BATCH, 3, 224, 224, device=device)
dummy_y = torch.randint(0, 1000, (BATCH,), device=device)

model.train()
print(f"Warming up ({WARMUP_STEPS} steps)...")
for _ in range(WARMUP_STEPS):
    optimizer.zero_grad()
    criterion(model(dummy_x), dummy_y).backward()
    optimizer.step()

torch.cuda.synchronize()
print(f"Benchmarking ({TIMED_STEPS} steps, batch={BATCH})...")
t0 = time.perf_counter()
for _ in range(TIMED_STEPS):
    optimizer.zero_grad()
    criterion(model(dummy_x), dummy_y).backward()
    optimizer.step()
torch.cuda.synchronize()
elapsed = time.perf_counter() - t0

throughput  = TIMED_STEPS * BATCH / elapsed
ms_per_step = elapsed / TIMED_STEPS * 1000

print()
print(f"Throughput  : {throughput:,.0f} samples / sec")
print(f"Latency     : {ms_per_step:.1f} ms / step")
print()
print("Benchmark complete.")
