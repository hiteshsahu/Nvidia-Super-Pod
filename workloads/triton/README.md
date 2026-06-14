# Triton Inference Server 🖲

Takes trained ML models and exposes them as a production inference API on the GPU node. Triton loads models from
`/mnt/data/model-repository` and serves them over three protocols simultaneously:

| Port | NodePort | Protocol   | Use                              |
|------|----------|------------|----------------------------------|
| 8000 | 30800    | HTTP/REST  | Standard inference requests      |
| 8001 | 30801    | gRPC       | High-throughput clients          |
| 8002 | 30802    | Prometheus | Scraped by kube-prometheus-stack |

Supported backends: TensorRT, ONNX Runtime, PyTorch, TensorFlow — drop the model file in and Triton handles the rest.

---

## ⚙️ Key Config Choices

| Flag                    | Value   | Reason                                                                    |
|-------------------------|---------|---------------------------------------------------------------------------|
| `--exit-on-error`       | `false` | One bad model won't take down the whole server                            |
| `--strict-model-config` | `false` | Triton infers config from the model file if `config.pbtxt` is absent      |
| `/dev/shm` mount        | 4 GiB   | Zero-copy IPC between client and server — avoids a GPU→CPU→GPU round-trip |

---

## 📦 Model Repository Layout

Place models on the host node before deploying:

```
/mnt/data/model-repository/
└── <model-name>/
    ├── config.pbtxt          # optional with --strict-model-config=false
    └── 1/
        └── model.plan        # TensorRT engine, or model.onnx / model.pt
```

---

## 🚀 Deploy 

```bash
kubectl apply -f workloads/triton/triton.yaml
kubectl rollout status deployment/triton -n inference
```

---

## 👨‍💻 Access

```bash
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}')

# Health check
curl http://$NODE_IP:30800/v2/health/ready

# List loaded models
curl http://$NODE_IP:30800/v2/models

# Metrics (scraped automatically by Prometheus via ServiceMonitor)
curl http://$NODE_IP:30802/metrics
```

---

## ⛔ Teardown

```bash
kubectl delete -f workloads/triton/triton.yaml
```
