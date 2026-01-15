# kube-montecarlo-jobs

A small **Kubernetes-focused job-processing demo** that showcases an API, background workers, and multiple deployment modes (local and AWS).

The system lets you submit Monte Carlo simulation jobs for stock price forecasting (randomized numerical simulations) via a web UI or API. Workers consume jobs from a queue, run a CPU-bound simulation, and store the results.

---

## Features

- **API + UI** built with FastAPI
- **Worker service** for CPU‑bound Monte Carlo simulations
- **Two runtime modes**:
  - **Local**: Redis for job storage and queueing
  - **AWS**: DynamoDB for storage and SQS for queueing
- **Deployment options**:
  - Docker Compose
  - Local Kubernetes
  - Single‑node Kubernetes on AWS EC2 (fully automated)

---

## Repository Structure

```
.
├── backend/            # FastAPI app, worker, runtime wiring
├── frontend/           # Minimal single‑page HTML UI (served from /)
├── k8s/
│   ├── local/          # Local Kubernetes manifests (includes Redis)
│   └── aws-ec2/        # AWS manifests (ECR images, SQS + DynamoDB)
├── infra/              # Terraform: VPC, EC2, DynamoDB, SQS
├── ansible/            # Installs Kubernetes via kubeadm on EC2
├── .github/workflows/  # CI/CD automation
├── docker-compose.yml  # Easiest way to run locally
├── aws_iam             # IAM roles and policies
└── README.md
```

---

## Running Locally

### Option A: Docker Compose (Recommended)

**Prerequisites**

- Docker
- Docker Compose

**Start the stack**

```bash
docker compose up --build
```

**Open**

- UI: http://localhost:8000/
- API docs (Swagger): http://localhost:8000/docs

**Stop**

```bash
docker compose down
```

---

### Option B: Python Virtual Environment (No Containers)

**Prerequisites**

- Python 3.10+ (recommended)
- A running Redis instance

**Start Redis (example)**

```bash
docker run --rm -p 6379:6379 redis:7
```

**Set up the virtual environment**

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

**Run the API (terminal 1)**

```bash
export APP_MODE=local
export REDIS_URL=redis://localhost:6379/0
uvicorn backend.main:app --host 0.0.0.0 --port 8000
```

**Run the worker (terminal 2)**

```bash
export APP_MODE=local
export REDIS_URL=redis://localhost:6379/0
python -m backend.worker
```

Open: http://localhost:8000/

---

## Running on AWS (Single‑Node Kubernetes on EC2)

This repository supports a fully automated AWS deployment using:

- **Terraform** (`infra/`) – VPC, EC2, DynamoDB, SQS
- **Ansible** (`ansible/`) – Kubernetes installation via kubeadm
- **Kubernetes manifests** (`k8s/aws-ec2/`) – API + worker
- **GitHub Actions** – provisioning, image builds, and deployment

---

### Prerequisites

- AWS account with permissions for:
  - IAM roles and policies
  - OIDC provider
  - ECR
  - S3
  - EC2 / VPC
  - DynamoDB
  - SQS
- A GitHub repository containing this project
- An EC2 SSH key pair (used by Terraform and Ansible)

---

### AWS Setup (Recommended: GitHub Actions)

#### 1. One‑time IAM Setup

The `aws_access/` scripts provide examples to bootstrap IAM:

- `create_oicd_provider.sh` – GitHub OIDC provider
- `create_infra_role.sh` – Terraform workflow role
- `create_ecr_role.sh` – ECR build/push role
- `create_runtime_role.sh` – EC2 instance role (SQS + DynamoDB access)

**Notes**

- Replace placeholders such as `ACCOUNT_ID` and `GITHUB_USERNAME`
- Update example ARNs in `create_runtime_role.sh` to match your region and resources

---

#### 2. Terraform State Bucket

Terraform uses an S3 backend:

- Bucket name: `kube-montecarlo-jobs`
- Default region: `us-west-2`

Create the bucket manually or update `infra/main.tf` to use a different backend.

---

#### 3. EC2 Key Pair

Terraform expects an EC2 key pair named:

```
kube-montecarlo-jobs
```

Create this key pair or update `key_name` in `infra/main.tf`.

---

#### 4. Create ECR Repositories

Create the following repositories (one time):

- `kube-montecarlo-jobs-api`
- `kube-montecarlo-jobs-worker`

---

#### 5. Configure GitHub Secrets and Variables

**GitHub → Settings → Secrets and variables → Actions**

**Variables**

- `AWS_REGION` (e.g. `us-west-2`)
- `AWS_AZ` (optional)
- `AWS_ROLE_ARN` (OIDC role for Terraform)

**Secrets**

- `EC2_SSH_PRIVATE_KEY` (private key for the EC2 instance, user `ubuntu`)

---

### Deployment Workflow Order

Run the following GitHub Actions workflows in order:

1. **Create infrastructure**
   - `create-infra` → `apply`

2. **Install Kubernetes**
   - `ansible-k8s`

3. **Build and push images**
   - `build-and-push-ecr` (or push to `main`)

4. **Deploy application**
   - `deploy-app`

The deploy step:

- Creates/updates a ConfigMap `app-config`
- Creates/updates the ECR pull secret `ecr-pull`
- Applies `k8s/aws-ec2/*.yaml`
- Replaces `REPLACE_ME_ECR_URI` with your actual ECR URI

---

### Accessing the App on AWS

The API is exposed via **NodePort 30080**.

```
http://<EC2_PUBLIC_IP>:30080/
```

---

### Tear Down (AWS)

To destroy infrastructure:

- Run `create-infra` → `destroy`

You may also manually delete:

- ECR repositories
- Terraform state S3 bucket

---

## Environment Variables

### Local Mode (Redis)

```
APP_MODE=local        # default
REDIS_URL=redis://localhost:6379/0
```

### AWS Mode (SQS + DynamoDB)

```
APP_MODE=aws
AWS_REGION=us-west-2
SQS_QUEUE_URL=<full queue URL>
DDB_TABLE_NAME=<table name>
```

In AWS mode, credentials are provided by the EC2 instance profile.

---

## API Reference

- `GET /` – Frontend UI
- `POST /api/jobs` – Create a job
  ```json
  {"ticker": "AAPL", "horizon_days": 30, "simulations": 10000}
  ```
- `GET /api/jobs` – List jobs
- `GET /api/jobs/{job_id}` – Get job details
- `GET /docs` – Swagger UI

---

## License

This project is licensed under the MIT License – see the [LICENSE](LICENSE) file for details.
