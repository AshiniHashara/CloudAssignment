# ADR-001: Kubernetes Node Instance Type

## Status
Accepted (revised)

## Context
CloudMart's EKS managed node group (`infra/modules/eks/main.tf`) hosts five
Deployments (frontend, product-service, order-service, user-service,
notification-service), each requesting modest CPU/memory but running a
minimum of 2 replicas in production with HPA headroom up to 6. The cluster
must stay inside the course's Free-Tier-oriented cost budget ($50/month
monthly budget alarm, `infra/modules/monitoring/main.tf`) while still having
enough headroom per node to schedule multiple service pods without
constant pending-pod pressure during HPA scale-out or rolling updates
(maxSurge: 1).

We compared three EC2 instance families for the worker node group:

| Type | vCPU | RAM | On-demand $/hr (us-east-1) | Architecture |
|---|---|---|---|---|
| t3.small | 2 | 2 GiB | ~$0.0208 | x86_64 |
| t3.medium | 2 | 4 GiB | ~$0.0416 | x86_64 |
| t4g.medium | 2 | 4 GiB | ~$0.0336 | ARM64 (Graviton2) |

This ADR originally chose t3.medium on capacity grounds (see "Original
reasoning" under Alternatives). That choice was invalidated by an actual
account-level restriction discovered during the first real `terraform
apply`: the node group failed with `AsgInstanceLaunchFailures` —
`InvalidParameterCombination - The specified instance type is not eligible
for Free Tier` — confirmed via `aws ec2 describe-instance-types --filters
"Name=free-tier-eligible,Values=true"`, which returned only
`t3.micro`, `t3.small`, `t4g.micro`, `t4g.small` (plus two `*-flex.large`
types) for this account. t3.medium and t4g.medium are both off the table
here regardless of their cost/capacity merits — this account, like the
GuardDuty restriction documented in `infra/environments/prod/terraform.tfvars`,
is a sandbox/academic account that hard-blocks non-Free-Tier resources.

## Decision
Use **t3.small** for the managed node group (2–6 nodes, desired 2) — it's
the only one of the three compared types this account will actually
provision.

## Consequences
**Easier:**
- This is the only option of the three that the account will actually let
  us provision at all — it isn't a tradeoff, it's a hard constraint.
- Cheapest of the three: ~$15/month for 2 nodes, leaving the most headroom
  under the $50 budget alarm.

**Harder:**
- 2 GiB RAM per node is tight once 5 services' replicas plus required
  DaemonSets (CNI, kube-proxy, CloudWatch agent) are scheduled on only 2
  nodes — more exposed to pods staying Pending during HPA scale-out or
  rolling updates than t3.medium would have been. Mitigated by keeping
  each service's resource `requests` modest (see each chart's
  `values.yaml`) and watching `kubectl get pods -n cloudmart-prod` during
  the load-test/autoscaling demo checkpoint for Pending pods; if that
  becomes a real problem, the node group's `max_size` (already 6) gives
  room to scale out nodes rather than resize them.

## Alternatives Considered
1. **t3.medium** — Original decision; rejected on retry. Doubles t3.small's
   RAM for the same vCPU, which would have given more scheduling headroom,
   but `aws_eks_node_group` creation fails outright on this account
   (`AsgInstanceLaunchFailures` / not Free-Tier-eligible). Not a
   cost/capacity tradeoff, an account-enforced exclusion.
2. **t4g.medium (Graviton, ARM64)** — Rejected on two independent grounds.
   First, the same Free-Tier restriction excludes it on this account.
   Second, even if it were available: all five service Dockerfiles use
   multi-stage builds with single-architecture base images
   (`python:3.11-slim`, `node:20-alpine`, `nginx:alpine`) and CI currently
   builds/pushes a single-arch image per service. Moving to Graviton nodes
   would require multi-arch image builds (`docker buildx`) across all five
   services and verifying every Python/Node native dependency has ARM64
   wheels/binaries. `t4g.small` *is* Free-Tier-eligible on this account, so
   this remains the natural next ADR/iteration once multi-arch CI is in
   place — likely a better long-term choice than t3.small on cost grounds
   alone (~$0.0168/hr vs ~$0.0208/hr).
