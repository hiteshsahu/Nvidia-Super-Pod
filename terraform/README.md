## Deploying Nvidia GPU Cluster on AWS

```mermaid
flowchart TB
    subgraph INTERNET["Internet"]
        USER["Your Machine\n84.169.x.x/32"]
    end

    subgraph AWS["AWS eu-central-1"]
        subgraph VPC["VPC 10.0.0.0/16"]
            IGW["Internet Gateway"]

            subgraph AZ1["Availability Zone 1"]
                PUB1["Public Subnet\n10.0.1.0/24"]
                PRIV1["Private Subnet\n10.0.10.0/24"]
                NAT1["NAT Gateway + EIP"]

                subgraph GPU_NODE["GPU Node (g4dn.xlarge)"]
                    EC2["EC2 Instance\nUbuntu 22.04"]
                    EIP["Elastic IP"]
                    ROOT["Root EBS gp3\n100 GB encrypted"]
                    DATA["Data EBS gp3\n200 GB encrypted\n/mnt/data"]
                    SG["Security Group\nSSH :22\nK8s API :6443\nGrafana :3000\nPrometheus :9090\nDCGM :9400\nNodePort :30000-32767"]
                    IAM["IAM Role\nSSM + CloudWatch\n+ S3 + ECR"]
                    CLOUD_INIT["cloud-init\nNVIDIA Driver 535\nCUDA 12-3\nDocker\nkubectl + Helm\nDCGM"]

                    subgraph K8S["Kubernetes — single-node (kubeadm)"]
                        GPU_OP["GPU Operator\nnvidia/gpu-operator v24.3\ndriver.enabled=false"]
                        DCGM["DCGM Exporter\n:9400 → ServiceMonitor"]
                        PROM["Prometheus\nkube-prometheus-stack"]
                        GRAFANA["Grafana\n:30300 NodePort\n11-panel GPU dashboard"]
                        TRITON["Triton Inference Server\n:30800 NodePort"]
                        PYTORCH["PyTorch Job\nResNet-50 benchmark\n~320 samples/sec"]
                        CUDA_JOB["CUDA Validation Job\nnvidia-smi + deviceQuery\n+ bandwidthTest"]
                    end
                end
            end

            subgraph AZ2["Availability Zone 2"]
                PUB2["Public Subnet\n10.0.2.0/24"]
                PRIV2["Private Subnet\n10.0.11.0/24"]
                NAT2["NAT Gateway + EIP"]
            end

            RT_PUB["Public Route Table\n0.0.0.0/0 → IGW"]
            RT_PRIV["Private Route Table\n0.0.0.0/0 → NAT"]
        end

        subgraph OBS["Observability"]
            CW["CloudWatch\nVPC Flow Logs\nGPU Util Alarm < 10%\nGPU Mem Alarm > 90%\nGPU Temp Alarm > 83°C"]
        end
    end

    USER -->|"SSH / HTTPS"| IGW
    IGW --> RT_PUB
    RT_PUB --> PUB1
    RT_PUB --> PUB2
    PUB1 --> NAT1
    PUB2 --> NAT2
    NAT1 --> RT_PRIV
    NAT2 --> RT_PRIV
    RT_PRIV --> PRIV1
    RT_PRIV --> PRIV2
    PUB1 --> GPU_NODE
    EIP --> EC2
    EC2 --- ROOT
    EC2 --- DATA
    EC2 --- SG
    EC2 --- IAM
    EC2 -. "first boot" .-> CLOUD_INIT
    CLOUD_INIT -. "ansible playbook 01" .-> K8S
    GPU_OP --> DCGM
    DCGM -->|"metrics"| PROM
    PROM -->|"datasource"| GRAFANA
    EC2 --> CW

    classDef compute fill:#ED7100,color:#fff,stroke:#b35500,stroke-width:2px
    classDef network fill:#8C4FFF,color:#fff,stroke:#5a1fcc,stroke-width:2px
    classDef storage fill:#3F8624,color:#fff,stroke:#2a5c18,stroke-width:2px
    classDef security fill:#DD344C,color:#fff,stroke:#aa1f35,stroke-width:2px
    classDef obs fill:#E7157B,color:#fff,stroke:#b00d5c,stroke-width:2px
    classDef user fill:#232F3E,color:#fff,stroke:#000,stroke-width:2px
    classDef k8s fill:#326CE5,color:#fff,stroke:#1A3F99,stroke-width:2px

    class EC2,CLOUD_INIT compute
    class IGW,NAT1,NAT2,RT_PUB,RT_PRIV,EIP,PUB1,PUB2,PRIV1,PRIV2 network
    class ROOT,DATA storage
    class SG,IAM security
    class CW obs
    class USER user
    class GPU_OP,DCGM,PROM,GRAFANA,TRITON,PYTORCH,CUDA_JOB k8s
```


- Network layer — VPC, public/private subnets across 2 AZs, IGW, NAT Gateways, route tables
- Compute layer — EC2 GPU node with Elastic IP, security group port rules, IAM role
- Storage — root EBS (100 GB) and data EBS (200 GB) both encrypted gp3
- Boot — cloud-init flow installing drivers, CUDA, Docker, kubectl
- Observability — CloudWatch alarms for GPU util, memory, and temperature + VPC flow logs
- Access — your IP locked down to SSH :22, K8s API :6443, and service ports

---

### main.tf : the core infrastructure.

Key design choices:
- Spot instance by default (`use_spot_instance = true`) — cuts cost from ~`$0.53/hr` to ~`$0.16/hr` on a T4, which matters for a lab project
- `IMDSv2 enforced` (http_tokens = "required") — security best practice NVIDIA will notice
- Separate data `EBS volume (200GB)` for datasets and model checkpoints — keeps root volume clean
- `CloudWatch alarm for low GPU` utilization for operational thinking, not just provisioning
- `IAM role with SSM access` — means you can shell in without opening SSH if needed

### variables.tf 
Validation blocks on instance_type and environment are deliberate. 

### outputs.tf 
Includes pre-built SSH command, all dashboard URLs, and a validate_gpu_command output.

After terraform apply you get everything you need printed directly.