# ADR-003: Deployment Strategy for product-service

## Status
Accepted

## Context

The `product-service` is the highest-traffic service in CloudMart: both the frontend and
the `order-service` call it during every product browse and every order placement. Any
downtime or correctness regression during deployment has an immediate, visible impact on
users. We need a deployment strategy that:

1. Minimises user-visible downtime during new version rollouts
2. Limits the blast radius of a bad release to a small fraction of traffic before it's caught
3. Provides an automatic rollback path if errors spike, without waiting on a human to notice
4. Is achievable with our actual CI/CD pipeline and cluster tooling (GitHub Actions, EKS,
   CloudWatch metrics already emitted by product-service)

`product-service` runs 2 replicas in production (scaling to 6 via HPA). RTO target: < 5
minutes. RPO target: 0 (stateless service; DynamoDB is the source of truth).

## Decision

We selected **Canary Deployment via Argo Rollouts**, replacing the standard Kubernetes
`Deployment` for `product-service` with an Argo `Rollout` object
(`k8s/charts/product-service/templates/rollout.yaml`).

Configuration:
```yaml
strategy:
  canary:
    steps:
      - setWeight: 20
      - pause: { duration: 2m }
      - setWeight: 50
      - pause: { duration: 2m }
      - setWeight: 100
    analysis:
      templates:
        - templateName: product-error-rate
      startingStep: 1
```

An `AnalysisTemplate` (`product-error-rate`) queries the `CloudMart/Services` CloudWatch
namespace for the `5xxErrorRate` metric on `product-service` every minute and halts the
rollout automatically if `result[0] > 1` (error rate exceeds 1%), instead of relying on a
human watching a dashboard during the rollout window.

This supersedes an earlier draft decision to use a plain rolling update
(`maxSurge: 1, maxUnavailable: 0`) for this service. Rolling update remains the strategy
for the other four services (order, user, notification, frontend), which see materially
less traffic and don't yet have a CloudWatch error-rate metric wired up to gate on.

## Consequences

**Positive:**
- New code only reaches 20% of traffic initially; a bad release affects a fifth of requests
  for at most 2 minutes before the automated analysis step can halt it — far smaller blast
  radius than a rolling update, where a bad pod can already be serving a third of traffic
  (1 of 2-3 pods) with no automatic gate
- The error-rate `AnalysisTemplate` removes the dependency on a human watching a dashboard
  during the rollout window; `kubectl argo rollouts get rollout product-service` shows the
  same status live during the demo (Demo Checkpoint 5/6)
- `kubectl argo rollouts undo` or `abort` gives an explicit rollback path distinct from
  Kubernetes' implicit rollout-undo semantics
- Satisfies the assignment's distinction-level requirement (Section 3.5 [D]) directly

**Negative:**
- Requires the Argo Rollouts controller and CRDs installed cluster-wide (additional
  component to operate, beyond what a vanilla EKS cluster provides) — owned by Member 4's
  cluster-prerequisites step
- Total rollout time is now ~4 minutes minimum (two 2-minute pauses) versus near-immediate
  for a rolling update — acceptable against our 5-minute RTO target, but slower
- The CloudWatch `5xxErrorRate` metric must actually be emitted correctly by
  product-service before the analysis step is meaningful; if that metric pipeline breaks,
  the safety gate silently has nothing to evaluate (mitigated by the existing CloudWatch
  alarm on the same metric, Section 3.6 [M])
- Adds YAML/CRD complexity (`Rollout` + `AnalysisTemplate`) that the other four services'
  plain `Deployment` manifests don't have, which the whole team needs to understand for
  the individual viva, not just whoever wrote it

## Alternatives Considered

### Option A: Rolling Update (`maxSurge: 1, maxUnavailable: 0`) — REJECTED
This was the original choice, and it's what the other four CloudMart services use. It's
zero-config (built into `Deployment`) and zero-downtime by construction. It was rejected
specifically for `product-service` because it has no traffic-percentage control or
automated error-rate gate: a bad pod can be serving live traffic as soon as it passes its
readiness probe, with detection and rollback left entirely to a human noticing the
CloudWatch alarm. For CloudMart's highest-traffic service, the extra ~3-4 minutes a canary
rollout takes is a worthwhile trade for an automated, metric-gated blast-radius limit.

### Option B: Blue/Green Deployment — REJECTED
Blue/green maintains two identical full environments and switches all traffic atomically.
It was rejected because it requires double the compute resources during deployment (4 pods
instead of 2) on an already cost-constrained t3.medium node group, and because it provides
no gradual traffic shift — a bad release still gets 100% of traffic immediately after the
switch, just with a faster rollback than rolling update. Canary's gradual weight shift plus
automated analysis addresses the actual risk (a bad release reaching all users) more
directly than blue/green's faster-rollback-after-the-fact approach.
