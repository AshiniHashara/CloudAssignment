# ADR-001: Kubernetes Node Instance Type

## Status
Accepted

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

## Decision
Use **t3.medium** for the managed node group (2–6 nodes, desired 2).

t3.medium doubles the RAM of t3.small for the same vCPU count, which
matters more than raw compute here: with 5 services × 2+ replicas plus
DaemonSets (CNI, kube-proxy, CloudWatch agent) on only 2 nodes at steady
state, t3.small's 2 GiB frequently leaves too little allocatable memory
once kube-reserved/system-reserved overhead is subtracted, causing pods to
stay Pending instead of scheduling. t3.medium's ~$30/month for 2 nodes
fits comfortably under the $50 budget alarm while leaving room for HPA to
scale out under load-test demonstrations.

t4g.medium (Graviton/ARM) is ~20% cheaper than t3.medium for the same
vCPU/RAM, but was rejected for this iteration — see Alternatives.

## Consequences
**Easier:**
- Pods schedule reliably at 2-node steady state without memory pressure.
- Headroom for the HPA demo (CPU-based scale-out 2→6 replicas) without
  needing to also scale nodes mid-demo.

**Harder:**
- ~2x the compute cost of t3.small ($30/month vs $15/month for 2 nodes),
  consuming a larger share of the $50 monthly budget.
- Missed the ~20% additional savings available from Graviton/ARM nodes.

## Alternatives Considered
1. **t3.small** — Rejected. Cheapest option, but 2 GiB RAM per node is too
   tight once 5 services' replicas plus required DaemonSets are scheduled
   on only 2 nodes; would force premature node scale-out (defeating the
   cost savings) or pod scheduling failures during the live demo.
2. **t4g.medium (Graviton, ARM64)** — Rejected for now, not on cost or
   capacity grounds (it wins on both) but on team risk: all five service
   Dockerfiles use multi-stage builds with single-architecture base images
   (`python:3.11-slim`, `node:20-alpine`, `nginx:alpine`) and CI currently
   builds/pushes a single-arch image per service. Moving to Graviton nodes
   would require multi-arch image builds (`docker buildx`) across all five
   services and verifying every Python/Node native dependency has ARM64
   wheels/binaries, which is more engineering risk than the assignment
   timeline justifies. This is the better long-term choice and is the
   natural next ADR/iteration once multi-arch CI is in place.
