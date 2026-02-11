# Configuration Decisions & Rationale

This document explains the key architectural and operational choices, why they were made, and what tradeoffs they introduce.

## Goals + Constraints

- Mandatory: AWS only, EKS only
- Mandatory: MySQL/MongoDB/Redis/Elasticsearch external to Kubernetes
- Mandatory: NGINX replaces Tutor's default Caddy edge
- Mandatory: CloudFront + WAF in front of the load balancer
- Mandatory: HPA for LMS/CMS, probes, backups, and observability
- Constraint: keep costs low (small instance sizes, minimal add-ons)
- Constraint: evidence-friendly (repeatable scripts, deterministic Terraform plans)

## Key Decisions

## Cluster and Networking

Kubernetes version:
- Choice: EKS `1.33`
- Rationale: stable EKS version with broad addon support; avoids "latest but unproven in this environment" risk during an assessment
- Tradeoff: not the newest version; upgrading is straightforward in EKS but should be tested (addons + workloads)

Node placement:
- Choice: worker nodes in private subnets; LoadBalancer (NLB) in public subnets
- Rationale: reduces attack surface; DB traffic stays inside the VPC
- Tradeoff: outbound access from private subnets requires NAT or VPC endpoints

EKS API endpoint:
- Choice: cluster endpoint remains public for simplicity in a short assessment timeline
- Rationale: easiest reproducibility for reviewers; avoids needing VPN/bastion
- Tradeoff: for real production, prefer private endpoint and restricted CIDRs

## External Data Layer

MySQL:
- Choice: RDS MySQL 8.0.x (non-Aurora)
- Rationale: matches Tutor/Open edX expectations; managed backups and maintenance
- Configuration: parameter group sets `utf8mb4` charset/collation to avoid Unicode issues

MongoDB/Redis/Elasticsearch:
- Choice: EC2 instances (private only)
- Rationale: mandated by the assessment ("Mongo/Redis/Elasticsearch on EC2 instance")
- Tradeoff: operational burden (patching, uptime, backups) vs managed services

Security groups:
- Choice: DB SGs only allow inbound from the EKS worker node SG
- Rationale: enforces "not publicly accessible" and limits lateral exposure
- Tradeoff: if node SG changes, DB SG references must be updated

Secrets:
- Choice: AWS Secrets Manager for DB credentials
- Rationale: avoids hardcoding secrets in repo or logs; supports rotation patterns
- Tradeoff: requires IAM permissions and careful "do not print secrets" discipline

S3 access from private subnets:
- Choice: enable S3 Gateway VPC endpoint (cheap, removes NAT dependency for S3)
- Rationale: backups/verification should not fail if NAT is absent or minimized
- Tradeoff: only covers S3; other outbound traffic still needs NAT

## Storage

Shared media/uploads:
- Choice: EFS (RWX) for `openedx-media` mounted into LMS/CMS at `/openedx/media`
- Rationale: LMS/CMS run with multiple replicas (HPA min=2); they must share uploads/media
- Tradeoff: EFS requires NFS (2049) and EFS CSI; snapshotting differs from EBS (use AWS Backup / EFS backup policy)

Single-writer PVCs:
- Choice: EBS gp3 (RWO) for Meilisearch PVC
- Rationale: simple, cost-effective for a single deployment replica
- Tradeoff: cannot be mounted by multiple pods at once

## Edge and Traffic Management

Ingress controller:
- Choice: ingress-nginx with a Service type `LoadBalancer` (AWS NLB)
- Rationale: NGINX is required, supports TLS termination, routing, and rate-limits via annotations
- Tradeoff: additional moving parts (controller, LB) vs simpler single-service exposure

Remove Caddy permanently:
- Choice: a post-render filter used by `infra/k8s/04-tutor-apply/apply.sh`
- Rationale: Tutor can regenerate Caddy resources on every render; post-render makes removal deterministic (no manual "disable script loops")
- Tradeoff: wrapper must be used consistently for apply operations

TLS termination:
- Choice: terminate TLS at NGINX ingress (self-signed for placeholder domains)
- Rationale: meets the requirement; keeps certificates at the edge
- Tradeoff: for real production, use real DNS + ACM and trust chain

## Scalability + Operations

HPA:
- Choice: HPA on `lms` and `cms` (min=2, max=6, CPU=70%)
- Rationale: required by assessment; demonstrates auto-scaling behavior under load
- Dependency: CPU-based HPA requires resource requests/limits and metrics-server
- Implementation detail: default deployment requests are tuned for reproducibility on `2 x t3.large`; for peak load screenshots, nodegroup desired size can be temporarily raised to 3

Health checks:
- Choice: liveness/readiness probes injected by post-render filter
- Rationale: required by assessment; avoids manual patching of Tutor output

Observability:
- Choice: kube-prometheus-stack + loki-stack (Grafana includes Loki datasource)
- Rationale: common, reviewer-recognizable; fast to validate with dashboards + logs
- Tradeoff: still requires tuning/alerting work for real production

CloudFront + WAF:
- Choice: CloudFront distribution in front of the ingress NLB with a WAF rule that blocks `X-Block-Me: 1`
- Rationale: meets requirement and provides simple, unambiguous proof (HTTP/2 403)
- Tradeoff: without real DNS/hostnames, default CloudFront requests can return 404 due to Ingress host routing
- Origin protocol: CloudFront uses HTTP-to-origin (`origin_protocol_policy = "http-only"`) because the NGINX Ingress uses a self-signed certificate for placeholder domains and CloudFront requires a publicly trusted cert for HTTPS-to-origin
- Hardening path: `infra/cloudfront-waf/apply.sh` supports `ORIGIN_PROTOCOL_POLICY=https-only` once a trusted origin certificate is in place

## What Would Be Hardened For Real Production (Not Required For Assessment)

- Real domains + ACM certificates for both CloudFront and Ingress hostnames
- Private EKS endpoint + restricted CIDRs; remove `0.0.0.0/0` publicAccessCidrs
- RDS Multi-AZ + longer retention + automated snapshots/restore drills
- Replace EC2 Redis with ElastiCache; EC2 Elasticsearch with OpenSearch (if allowed)
- Patch management and automated AMI updates for EC2 data nodes
- Network policies, resource quotas/limits per namespace
- Centralized secrets injection (External Secrets Operator) and rotation workflows
