# Architecture & Network Flow

This document describes the deployed topology, request flow, and operational boundaries.

## Scope

- Region: `us-east-1`
- EKS cluster: `openedx-eks`
- Namespaces:
  - `openedx-prod` (Open edX workloads)
  - `ingress-nginx` (ingress controller)
  - `observability` (Prometheus/Grafana/Loki)
- Public hostnames (production path):
  - `lms.<domain>`
  - `studio.<domain>`
  - `apps.lms.<domain>`
- Databases are external to Kubernetes and private-only:
  - RDS MySQL
  - EC2 MongoDB
  - EC2 Redis
  - EC2 Elasticsearch

## Components

Edge:
- Authoritative DNS zone (Route53 or external registrar DNS) for `lms/studio/apps` records
- CloudFront + WAF (edge security path)
- NLB from ingress-nginx `LoadBalancer` service
- NGINX Ingress Controller (TLS termination for direct ingress path)

Application (`openedx-prod`):
- `lms`, `cms`, `mfe`, `lms-worker`, `cms-worker`, `smtp`
- HPA on `lms` and `cms`

Storage/Data:
- EFS RWX PVC for `/openedx/media`
- External MySQL/Mongo/Redis/Elasticsearch

Observability:
- kube-prometheus-stack (Prometheus, Alertmanager, Grafana)
- Loki stack

## Diagram 1: Edge & DNS Flow

```mermaid
flowchart LR
  U[User Browser]
  DNS[DNS zone Route53 or registrar]
  CF[CloudFront]
  WAF[WAF WebACL]
  NLB[NLB ingress]
  NGX[NGINX ingress controller]

  U --> DNS
  DNS -->|lms studio apps| CF
  DNS -->|direct validation path| NLB

  WAF -. attached .-> CF
  CF -->|origin HTTP currently| NLB
  NLB --> NGX
```

TLS note:
- Viewer TLS: browser to CloudFront, and browser to NLB/NGINX on direct ingress path.
- Origin TLS (CloudFront to NGINX) is currently `http-only` by design in this repo and can be hardened to `https-only` once origin hostname/certificate alignment is in place.

## Diagram 2: Kubernetes Runtime Flow

```mermaid
flowchart TB
  subgraph EKS[openedx-eks]
    subgraph NS1[ingress-nginx]
      NGX[NGINX ingress]
    end

    subgraph NS2[openedx-prod]
      LMS[LMS]
      CMS[CMS Studio]
      MFE[MFE]
      LMSW[LMS worker]
      CMSW[CMS worker]
      SMTP[SMTP relay]
      HPA[HPA lms and cms]
    end

    subgraph NS3[observability]
      PROM[Prometheus]
      GRAF[Grafana]
      LOKI[Loki]
      ALERT[Alertmanager]
    end
  end

  NGX --> LMS
  NGX --> CMS
  NGX --> MFE

  LMS -. metrics .-> PROM
  CMS -. metrics .-> PROM
  LMSW -. logs .-> LOKI
  CMSW -. logs .-> LOKI
  GRAF --> PROM
  GRAF --> LOKI
  PROM --> ALERT
```

## Diagram 3: Data, AZ, and Egress View

```mermaid
flowchart LR
  subgraph AZA[us-east-1a]
    NODA[EKS nodes]
    REDIS[Redis EC2]
  end

  subgraph AZC[us-east-1c]
    NODC[EKS nodes]
    MONGO[Mongo EC2]
    ES[Elasticsearch EC2]
  end

  RDS[RDS MySQL Multi-AZ]
  EFS[EFS regional RWX]
  NAT[NAT gateway single]
  NET[Public internet APIs]
  S3EP[S3 gateway endpoint optional]
  S3[S3]

  NODA --> RDS
  NODC --> RDS
  NODA --> MONGO
  NODC --> MONGO
  NODA --> REDIS
  NODC --> REDIS
  NODA --> ES
  NODC --> ES

  NODA --> EFS
  NODC --> EFS

  NODA --> NAT
  NODC --> NAT
  NAT --> NET

  NODA --> S3EP
  NODC --> S3EP
  S3EP --> S3
```

## Ports and Access Matrix

| From | To | Port | Purpose |
|---|---|---:|---|
| Internet | CloudFront | 443 | viewer traffic |
| CloudFront | NLB | 80 | origin path (current setting) |
| Internet | NLB | 443 | direct ingress validation path |
| NGINX Ingress | LMS/CMS services | 8000 | app routing |
| Open edX pods | RDS MySQL | 3306 | relational DB |
| Open edX pods | MongoDB | 27017 | modulestore/content data |
| Open edX pods | Redis | 6379 | cache/broker |
| Open edX pods | Elasticsearch | 9200 | search backend |
| EKS nodes | EFS mount targets | 2049 | shared media RWX |

## Current Hardening Status

Production-style and implemented:
- Real domain routing
- Let’s Encrypt certificates via cert-manager
- NGINX ingress replacing edge Caddy
- EKS endpoint hardening (private access enabled + public access CIDR restricted)
- External data layer outside Kubernetes
- RDS Multi-AZ
- HPA/probes/observability/backups

Still not fully enterprise-hard (known gaps):
- Mongo/Redis/Elasticsearch are single EC2 instances
- CloudFront origin protocol currently `http-only`
- NAT is single gateway (not highly available)

## Hardening Path (if required)

1. Increase RDS backup retention and automate restore drills.
2. Move Redis/Elasticsearch to managed multi-AZ services if allowed, or add replication/failover on EC2.
3. Move CloudFront origin to `https-only` with certificate-hostname alignment.
4. Use multi-NAT design for AZ fault tolerance.
