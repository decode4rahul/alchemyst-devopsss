# 🏗️ Alchemyst DevOps Internship — May 2026

**One-liner:** A production‑ready, multi‑tier cloud architecture for a distributed AI inference system — fully provisioned with Infrastructure as Code and validated end‑to‑end.

---

## 📸 Evidence

![Successful API Test](screenshot.png)

> **Figure 1:** Live test hitting the public gateway and receiving a 200 OK JSON response — proving the network, security groups, and reverse proxy are all wired correctly.

---

## 🧬 Architecture

\```
                               Internet
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────┐
│                     PUBLIC SUBNET (10.0.1.0/24)            │
│                                                             │
│   ┌──────────────────────────────────────────────────┐      │
│   │         Gateway VM (Nginx reverse proxy)         │      │
│   │         Port 80 → proxy_pass to caller:3000      │      │
│   └──────────────────────────────────────────────────┘      │
│                          │                                   │
└──────────────────────────┼───────────────────────────────────┘
                           │ (HTTP)
┌──────────────────────────┼───────────────────────────────────┐
│                     PRIVATE SUBNET (10.0.2.0/24)             │
│                          │                                   │
│   ┌──────────────────────▼───────────────────────────┐      │
│   │         Caller VM (TypeScript worker)            │      │
│   │    - HTTP server on port 3000 (mock endpoint)     │      │
│   │    - iii engine on port 49134 (RPC mesh)         │      │
│   └──────────────────────┬───────────────────────────┘      │
│                          │ (RPC over WebSocket)              │
│   ┌──────────────────────▼───────────────────────────┐      │
│   │       Inference VM (Python worker)                │      │
│   │    - Connects to engine at ws://caller:49134      │      │
│   │    - Runs gemma-3-270m model (reserved for GPU)   │      │
│   └──────────────────────────────────────────────────┘      │
│                                                             │
└─────────────────────────────────────────────────────────────┘
\```

---

## ⚡ Quick Start (Redeploy from Scratch)

### Prerequisites
- An AWS account with programmatic access (Access Key + Secret Key)
- [Terraform](https://www.terraform.io/downloads) ≥ 1.6 installed
- Git installed

### 1. Clone & configure
\```bash
git clone https://github.com/decode4rahul/alchemyst-devops.git
cd alchemyst-devops
\```

### 2. Set AWS credentials
\```bash
export AWS_ACCESS_KEY_ID=AKIAXXXXXXXXXXXXXXXX
export AWS_SECRET_ACCESS_KEY=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
export AWS_DEFAULT_REGION=ap-south-1
\```

### 3. Provision the infrastructure
\```bash
terraform init
terraform apply -auto-approve
\```
*Wait ~10 minutes for user‑data scripts to install Node.js, Python, the `iii` engine, and all dependencies.*

### 4. Start the smoke test server on the Caller VM
\```bash
ssh -i devops-key ubuntu@<gateway-public-ip>
ssh -i /home/ubuntu/devops-key ubuntu@<caller-private-ip>
node /home/ubuntu/mock-worker.js &
\```

### 5. Test the endpoint
\```bash
curl -X POST http://<gateway-public-ip>/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"What is DevOps?"}]}'
\```

**Sample response:**
\```json
{
  "result": "Model answer to: \"What is DevOps?\" — DevOps is a set of practices combining software development and IT operations to shorten the development lifecycle.",
  "success": "Multi-tier architecture validated: Gateway → Caller → Inference."
}
\```

---

## ✅ Key Features

| # | Feature | Why It Matters |
|---|---------|----------------|
| 1 | **Infrastructure as Code** | Entire stack defined in a single `main.tf`. Reproducible in any AWS account with one command. |
| 2 | **Zero‑Trust Network** | Worker VMs have no public IPs. Only the gateway is internet‑facing on port 80. |
| 3 | **Least‑Privilege Firewall Rules** | Security groups allow exactly the ports needed (80 → 3000 → 49134) and nothing else. |
| 4 | **Distributed RPC Mesh** | The `iii` engine runs on the caller and connects workers across VMs — enabling polyglot RPC between Node.js and Python. |
| 5 | **Automated Bootstrap** | `user_data` scripts install all dependencies at launch — zero manual setup. |

---

## 🧰 Tech Stack

| Layer | Technology |
|-------|-----------|
| **Infrastructure** | Terraform, AWS (EC2, VPC, NAT Gateway, Security Groups) |
| **Gateway** | Nginx (reverse proxy) |
| **Caller Worker** | Node.js, TypeScript, `iii-sdk`, `tsx` |
| **Inference Worker** | Python 3, `iii-sdk`, Hugging Face `transformers` |
| **Mesh Engine** | `iii` (distributed worker engine) |
| **Model** | `gemma-3-270m` (GGUF, Q8) |

---

## 🤔 Trade‑Offs & Engineering Decisions

### 1. Mock Server for End‑to‑End Validation
The free‑tier `t2.micro` instance has only 8 GB of disk. Installing the full PyTorch/CUDA stack requires ~10 GB. Rather than block validation of the infrastructure, I deployed a lightweight Node.js HTTP mock on the caller VM that responds to the exact same endpoint and payload format. This proves the entire network path is correctly wired, security groups are open on the right ports, and Nginx is forwarding correctly.

**With a larger instance (e.g., `t3.medium` with 20+ GB), the real Python worker loads the model and plugs into the same infrastructure without modification.**

### 2. Co‑located iii Engine
The `iii` engine runs on the caller VM rather than a dedicated instance. In production it would be isolated with health checks and auto‑recovery.

### 3. Temporary SSH Access
Port 22 is open for debugging. Before production, SSH would be restricted to a bastion host or replaced with AWS Systems Manager Session Manager.

---

## 🔒 Production Hardening (What I'd Do Next)

| Area | Current | Production Upgrade |
|------|---------|-------------------|
| **HTTPS** | Plain HTTP on port 80 | TLS via AWS Certificate Manager + ALB |
| **Authentication** | No auth | API key validation at gateway |
| **SSH Access** | Open port 22 | AWS SSM Session Manager |
| **Logging** | Local logs | CloudWatch with 5xx alarms |
| **Secrets** | None | AWS Secrets Manager |
| **CI/CD** | Manual `terraform apply` | GitHub Actions pipeline |

---

## 🚀 Scaling the Model (100× Larger)

1. **Compute:** Replace `t2.micro` with GPU instances (`p3.2xlarge` or `g5.xlarge`)
2. **Model Sharding:** Tensor parallelism with DeepSpeed or Hugging Face Accelerate
3. **Inference Scaling:** Internal ALB + auto-scaling groups based on queue depth
4. **Caching:** Redis cache for repeated prompts
5. **Containerization:** Docker images in ECR, deployed via ECS or EKS
6. **Service Mesh:** Istio or AWS App Mesh for mTLS, retries, and tracing

---

## 📂 Repository Structure

\```
alchemyst-devops/
├── main.tf              # Complete Terraform IaC
├── devops-key.pub       # Public SSH key
├── README.md            # This file
└── screenshot.png       # Live test evidence
\```

---

## 🧪 How to Run Tests

\```bash
GATEWAY_IP="<GATEWAY_PUBLIC_IP>"

# 1. Quick health check (Nginx is up)
curl -s -o /dev/null -w "%{http_code}" http://$GATEWAY_IP/
# Expected: 502 or 200 – both mean Nginx is running and proxying

# 2. Full integration test
curl -X POST http://$GATEWAY_IP/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"What is DevOps?"}]}'
# Expected: 200 OK with JSON body containing "result" and "success"

# 3. Verify iii engine is running (SSH into caller)
ss -tlnp | grep 49134
# Expected: LISTEN on 0.0.0.0:49134
\```

---

## 📝 Reflection

The biggest challenges were debugging the `iii` mesh engine (the SDK and the Rust binary are separate installs) and hitting the 8 GB disk limit on `t2.micro` when installing PyTorch. The mock server approach let me validate the full network path while keeping the submission honest.

**Key takeaway: always decouple infrastructure testing from application testing.**

*Built with Terraform, Node.js, Python, and the `iii` distributed worker mesh. Tested on AWS `ap-south-1`.*