# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

CloudMart is a microservices e-commerce platform for **IS 4630 Cloud Infrastructure Management** (University of Moratuwa). The assignment deploys it to **AWS** using EKS, Terraform-managed infrastructure, and cloud-managed data stores. Requirements are graded **[M] Mandatory**, **[R] Recommended**, or **[D] Distinction**.

## Local Development

```bash
# Start all services (no cloud credentials needed — uses in-memory backends)
docker compose up --build

# Access at http://localhost:3000
# Demo credentials: alice@cloudmart.example / password123

# Health check individual services
curl http://localhost:8001/health   # product-service
curl http://localhost:8002/health   # order-service
curl http://localhost:8003/health   # user-service
curl http://localhost:8004/health   # notification-service

# Rebuild a single service
docker compose up --build product-service
```

## Services

| Service | Port | Language | Entry Point |
|---------|------|----------|-------------|
| product-service | 8001 | Python/Flask | `services/product-service/app.py` |
| order-service | 8002 | Node.js/Express | `services/order-service/src/index.js` |
| user-service | 8003 | Python/Flask | `services/user-service/app.py` |
| notification-service | 8004 | Node.js | `services/notification-service/src/index.js` |
| frontend | 3000→80 | React/Nginx | `services/frontend/src/` |

## Cloud Adapter Pattern

Every service defaults to in-memory backends and switches via environment variables. The class/function stubs are already in the source files — the task is implementing the bodies.

| Service | Env Var | Values | Where to Implement |
|---------|---------|--------|--------------------|
| product-service | `STORE_BACKEND` | `memory` → `dynamodb` | `DynamoDBStore` class in `app.py` |
| order-service | `QUEUE_BACKEND` | `memory` → `sqs` | `publishOrderEvent()` in `src/index.js` |
| user-service | `DB_BACKEND` | `memory` → `postgres` | `DB_HOST/PORT/NAME/USER/PASSWORD` |
| notification-service | `QUEUE_BACKEND` + `EMAIL_BACKEND` | `memory`/`console` → `sqs`/`ses` | `src/index.js` queue consumer |

DynamoDB table: `DYNAMODB_TABLE`. SQS queue: `SQS_QUEUE_URL`. Email sender: `FROM_EMAIL`.

## Infrastructure (Terraform)

All Terraform lives under `infra/`. Update `infra/backend.tf` with your group's S3 bucket name before `terraform init`. State is locked via DynamoDB.

```bash
terraform -chdir=infra init
terraform -chdir=infra plan
terraform -chdir=infra apply
```

Module layout:
- `infra/modules/vpc/` — VPC (10.0.0.0/16), 3-tier subnets across 2 AZs (public, private-app for EKS, private-data for RDS), NAT GWs per AZ, VPC Flow Logs, VPC endpoints for DynamoDB/S3/ECR/Secrets Manager
- `infra/modules/eks/` — EKS 1.29 cluster, managed node group (t3.medium, 2–6 nodes), IMDSv2 enforced, OIDC provider for IRSA
- `infra/modules/eks/irsa.tf` — IRSA roles scoped per service: product→DynamoDB, order→SQS send, notification→SQS recv+SES, user→Secrets Manager read-only
- `infra/modules/rds/` — PostgreSQL for user-service (private-data subnet)
- `infra/modules/dynamodb/` — Products table
- `infra/modules/sqs/` — Orders queue
- `infra/modules/kms/`, `infra/modules/ecr/`, `infra/modules/secrets/`, `infra/modules/ses/`
- `infra/modules/monitoring/` — CloudWatch log groups per service, SNS alert topic, monthly budget alarm ($50, alerts at 80%)

## Kubernetes

Manifests in `k8s/`. Two namespaces: `cloudmart-prod` (production) and `cloudmart-staging` (staging).

```bash
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/
```

Key patterns in existing manifests:
- `ConfigMap/cloudmart-config` for non-secret env vars — update `memory` values to cloud backend values after infrastructure is provisioned
- Image placeholders like `<YOUR-REGISTRY>/order-service:latest` — replace with ECR URI
- `serviceAccountName` is commented out with `# TODO` in each Deployment — wire to IRSA service accounts after `terraform apply`
- All production Deployments have min 2 replicas, rolling update (maxSurge:1, maxUnavailable:0), liveness + readiness probes, resource requests/limits, and HPA (2–6 replicas at 60% CPU)

Required additions not yet in `k8s/`:
- **[M]** `network-policy.yaml` — default-deny for `cloudmart-prod` namespace + explicit allow rules per inter-service path
- **[M]** Secrets injection via Secrets Store CSI Driver or External Secrets Operator
- **[M]** Ingress resource with ALB controller annotations
- **[R]** Pod Disruption Budgets (min 1 replica available per production deployment)

## Security

IRSA binds each Kubernetes ServiceAccount to a least-privilege IAM role — the binding is namespace+serviceaccount scoped (e.g., `system:serviceaccount:cloudmart-prod:product-service`). The K8s ServiceAccount name must exactly match what's declared in `infra/modules/eks/irsa.tf`.

Required additions:
- **[M]** Default-deny NetworkPolicy + explicit allow rules reflecting inter-service communication diagram
- **[R]** WAF attached to ALB with managed rule sets
- **[R]** GuardDuty enabled; document at least one finding and response
- **[D]** OPA/Gatekeeper or Kyverno — prevent root containers, privileged containers, images outside ECR

## CI/CD & Branch Strategy

Branch strategy: `main` → deploys to `cloudmart-prod`, `develop` → deploys to `cloudmart-staging`, `feature/*` → PRs only.

Pipeline must perform (per push to `main`/`develop`):
1. Lint + unit tests per service
2. Docker build + push to ECR (tag: commit SHA)
3. Trivy vulnerability scan — CRITICAL findings fail the pipeline
4. Kubernetes manifest validation (`kubeval` or `kubeconform`)
5. Deploy to staging (`develop`) or production (`main`) via rolling update with health-check gate
6. **[R]** Manual approval gate before production deploy
7. **[R]** Post-deploy smoke test (health check each `/ready` endpoint)

Pipeline config goes in `.github/workflows/`.

## Required Resource Tags

All AWS resources must carry these tags:

```
Project=cloudmart
Environment=prod|staging
Team=<your-group-id>
Owner=<email>
```

## Architecture Decision Records (ADRs)

Three ADRs are required, in Markdown format at `/docs/adr/ADR-NNN-title.md`, using Nygard format (Status / Context / Decision / Consequences / Alternatives Considered):

| # | Topic |
|---|-------|
| ADR-001 | Kubernetes node instance type (compare ≥3 types: cost, vCPU/RAM, ARM savings) |
| ADR-002 | Database technology for user-service (managed PostgreSQL vs NoSQL vs serverless relational) |
| ADR-003 | Deployment strategy for product-service (rolling vs blue/green vs canary) |

## Deliverables Checklist

Repository must contain:
- `infra/` — all Terraform
- `k8s/` — all Kubernetes manifests (or Helm charts `[R]`)
- `services/<name>/` — source + Dockerfile per service
- `.github/workflows/` — CI/CD pipeline
- `docs/adr/` — 3 ADRs
- `README.md` — cloud provider, deployment instructions, team members + contributions

## Demo Checkpoints (20 min)

| # | Area | What to Show |
|---|------|-------------|
| 1 | Infrastructure | `kubectl get nodes` (2+ Ready), `kubectl get pods -n cloudmart-prod` (all Running) |
| 2 | End-to-End | Register user → browse → place order → verify confirmation email |
| 3 | Networking | Subnet layout in console; prove DB is not public-internet accessible |
| 4 | Security | `kubectl get networkpolicy -n cloudmart-prod`; workload identity binding in console; GuardDuty/threat detection dashboard |
| 5 | CI/CD | Push small code change to `develop`; show pipeline run; verify change in staging |
| 6 | Autoscaling | Load test with `hey`/`k6` against product-service; show `kubectl get hpa -w` scaling |
| 7 | Observability | Live monitoring dashboard; trigger 404; show it in log query results |
| 8 | Cost | Cost dashboard with tags; daily spend breakdown; budget alert; unit economics (cost per 1,000 orders) |
| 9 | Disaster Recovery | Show DB automated backup; restore to point-in-time on a test instance; Velero restore commands |

## Key Constraints

- EKS nodes are in private-app subnets; RDS is in private-data (no internet route). Inter-service calls use Kubernetes DNS (`http://product-service:8001`).
- `endpoint_public_access = true` on EKS cluster is flagged for removal once a bastion is in place.
- notification-service has no inbound HTTP — it only polls SQS and calls SES outbound. Its K8s Service should be omitted or headless.
- The individual viva carries 40% of the total mark — every team member must understand the complete system.
