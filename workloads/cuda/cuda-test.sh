#!/usr/bin/env bash

# Copyright 2026 Hitesh Kumar Sahu — https://hiteshsahu.com
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

echo "============================================"
echo " CUDA Validation — $(date)"
echo "============================================"

echo ""
echo "--- nvidia-smi ---"
nvidia-smi

echo ""
echo "--- CUDA version ---"
nvcc --version 2>/dev/null \
  || echo "nvcc not in PATH (base image; driver confirmed via nvidia-smi)"

echo ""
echo "--- deviceQuery ---"
/opt/cuda-samples/Samples/1_Utilities/deviceQuery/deviceQuery

echo ""
echo "--- bandwidthTest (H2D / D2H / D2D) ---"
/opt/cuda-samples/Samples/1_Utilities/bandwidthTest/bandwidthTest --memory=pinned

echo ""
echo "All GPU validation checks PASSED."
