# ADR-002: Database Technology for user-service

## Status
Accepted

## Context

The `user-service` is a Python/Flask application responsible for user registration, JWT-based
login, and profile management. Passwords are hashed with bcrypt. The data model is clearly
relational: a `users` table with fixed columns (id, name, email, hashed_password, created_at,
updated_at), strong uniqueness constraint on email, and no requirement for schema flexibility.

Key requirements:
- ACID transactions required: failed user registration must not leave partial records
- Email uniqueness must be enforced at the database level (not just application level)
- Passwords stored as bcrypt hashes (fixed-length strings); no binary blob storage needed
- Query patterns: lookup by email (login), lookup by ID (profile); no complex joins or aggregations
- User data is sensitive PII; encryption at rest and TLS in transit are mandatory
- The assignment mandates managed cloud databases to avoid self-managing database servers

## Decision

We selected **Amazon RDS for PostgreSQL** (db.t3.micro) as the managed relational
database for the `user-service`.

Configuration:
- Engine: PostgreSQL 15
- Instance class: `db.t3.micro` (2 vCPU, 1 GB RAM) — Free Tier eligible
- Storage: 20 GB gp2, encrypted with the project KMS key
- Multi-AZ: **disabled** — this account enforces AWS Free Tier restrictions and
  rejects Multi-AZ RDS instances outright (`FreeTierRestrictionError` on
  `CreateDBInstance`), confirmed on the first real `terraform apply`. Originally
  planned as enabled for production (see "Negative" below); not actually
  available on this account regardless of environment.
- Automated backups: 1-day retention — the same account restriction also
  rejects `backup_retention_period > 1` with `FreeTierRestrictionError`;
  originally planned as 7 days for production.
- Parameter group: `ssl=1` enforced (rejects unencrypted connections)
- Credentials stored in AWS Secrets Manager; user-service retrieves them via IRSA

## Consequences

**Positive:**
- PostgreSQL provides ACID guarantees: email uniqueness constraints and transactions are
  enforced at the database level, preventing race conditions on concurrent registrations
- The user-service starter code already uses SQLAlchemy ORM with a PostgreSQL adapter;
  minimal code changes required to swap from the in-memory store
- RDS Free Tier (db.t3.micro, 20 GB) means zero additional cost during the project period
- Point-in-time recovery is still available within the 1-day backup window this account allows

**Negative:**
- No Multi-AZ failover and only 1-day backup retention — this account's Free
  Tier enforcement blocks both regardless of environment, so the demo's
  disaster-recovery story relies entirely on the 1-day automated backup window
  plus the separate Velero-based K8s backup (`infra/modules/backup`), not RDS
  Multi-AZ failover as originally planned.
- RDS requires placement in the private data subnet and a Security Group allowing port 5432
  from EKS nodes only; this adds infrastructure complexity (already handled by Terraform modules)
- db.t3.micro has limited RAM (1 GB); connection pooling must be used (PgBouncer or
  SQLAlchemy's pool) to avoid exceeding max_connections (~87 on t3.micro)
- Cold start time for RDS (~5 minutes) is longer than a NoSQL alternative; this affects
  disaster recovery RTO slightly

## Alternatives Considered

### Option A: Amazon DynamoDB (NoSQL) — REJECTED
DynamoDB would provide serverless, on-demand pricing and no connection limits. However,
the user-service data model is fundamentally relational: enforcing email uniqueness in DynamoDB
requires application-level conditional writes, which are more complex and do not provide
true ACID isolation across multiple attributes. The assignment starter code uses SQLAlchemy,
which does not support DynamoDB natively, requiring a full rewrite of the data layer.
Additionally, DynamoDB's eventual consistency model (unless using strongly consistent reads,
which have higher cost) is unsuitable for authentication, where a user who just registered
must immediately be able to log in.

### Option B: Amazon Aurora Serverless v2 (PostgreSQL-compatible) — REJECTED
Aurora Serverless v2 offers auto-scaling ACUs (Aurora Capacity Units) from 0.5 ACU up,
which is attractive for variable academic workloads. However, the minimum cost (~$0.12/hour
per ACU-hour, even at minimum capacity) is approximately 6× more expensive than db.t3.micro
for our low-traffic project. Aurora also does not qualify for the RDS Free Tier. The operational
benefits (auto-scaling, zero-downtime patching) are valuable in production but overkill for
a five-service university assignment with predictable, low traffic.
