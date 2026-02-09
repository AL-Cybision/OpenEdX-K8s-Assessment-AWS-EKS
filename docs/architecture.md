# Architecture & Network Flow

This document explains what is deployed, where it runs (AWS/Kubernetes), and how traffic/data flows through the system.

## Scope

- Region: `us-east-1`
- EKS cluster: `openedx-eks`
- Kubernetes namespaces:
- `openedx-prod` (Open edX workloads)
- `ingress-nginx` (NGINX Ingress Controller)
- `observability` (Prometheus/Grafana + Loki)
- Domains (placeholders for assessment): `lms.openedx.local`, `studio.openedx.local`
- Databases are external to Kubernetes (RDS + EC2), private only.

## Components (By Layer)

Edge + security:
- AWS WAF attached to CloudFront (header-based block rule for proof)
- CloudFront distribution (origin: the ingress NLB)
- AWS NLB created by `ingress-nginx` Service type `LoadBalancer`
- NGINX Ingress Controller terminates TLS and routes to services

Application (EKS pods in `openedx-prod`):
- LMS deployment + service
- CMS (Studio) deployment + service
- LMS/CMS workers (Celery) deployments
- MFE deployment + service
- SMTP deployment + service

Data layer (external to Kubernetes, private only):
- RDS MySQL 8.0.x (Open edX relational DB)
- MongoDB (EC2) for Open edX document store
- Redis (EC2) for cache/broker
- Elasticsearch (EC2) for search backend (enabled via Tutor plugin)

Storage:
- EFS (RWX) for shared media/uploads mounted into LMS/CMS at `/openedx/media`
- EBS gp3 (RWO) for single-writer PVCs (Meilisearch)

Observability:
- kube-prometheus-stack (Prometheus, Grafana, Alertmanager)
- Loki + Promtail (cluster log collection)

Backups:
- RDS snapshots (manual)
- EC2 EBS snapshots (manual)
- EBS-backed PV snapshots (manual)
- EFS media: AWS Backup / EFS backup policy (documented)

## Kubernetes Layout (What Runs Where)

`ingress-nginx`:
- Deployment: `ingress-nginx-controller` (replicas=2)
- Service: `ingress-nginx-controller` (type `LoadBalancer` -> NLB)

`openedx-prod`:
- Deployments: `lms`, `cms`, `lms-worker`, `cms-worker`, `mfe`, `smtp`, `meilisearch`
- Ingress: `openedx` (hosts `lms.openedx.local`, `studio.openedx.local`)
- HPA: `lms-hpa`, `cms-hpa` (min=2, max=6, CPU target 70%)
- PVC: `openedx-media` (RWX, EFS) and `meilisearch` (RWO, EBS gp3)

`observability`:
- Helm releases: `kube-prometheus-stack`, `loki-stack`
- Grafana includes Prometheus + Loki data sources (Loki auto-provisioned)

## Network + Security Model

Subnets:
- NLB runs in public subnets (created/managed by AWS)
- EKS worker nodes run in private subnets
- EC2 DB instances + RDS run in private subnets

Security groups (SG) intent:
- DB SGs do not allow public access and only allow inbound from the EKS worker node SG
- EFS SG allows NFS (2049/tcp) inbound from the EKS worker node SG

Ports (high-level):
- Internet -> CloudFront: 443
- CloudFront -> NLB: 443 (to NGINX Ingress)
- NGINX -> LMS/CMS services: 8000/tcp
- Pods -> RDS MySQL: 3306/tcp
- Pods -> MongoDB: 27017/tcp
- Pods -> Redis: 6379/tcp
- Pods -> Elasticsearch: 9200/tcp
- Pods -> EFS mount targets: 2049/tcp

## Ports and Access Matrix

This table summarizes the minimum required network paths for the deployment.

| From | To | Port | Why |
|---|---|---:|---|
| Internet | CloudFront | 443 | public entrypoint |
| CloudFront | NLB (ingress-nginx) | 443 | edge to origin |
| NLB | NGINX Ingress Controller pods | 443/80 | TLS termination + routing |
| NGINX Ingress | LMS/CMS services | 8000 | app traffic |
| LMS/CMS/Workers pods | RDS MySQL | 3306 | relational DB |
| LMS/CMS/Workers pods | MongoDB EC2 | 27017 | document store |
| LMS/CMS/Workers pods | Redis EC2 | 6379 | cache/broker |
| LMS/CMS pods | Elasticsearch EC2 | 9200 | search |
| EKS worker nodes | EFS mount targets | 2049 | RWX media/uploads |

Security note:
- DB/EFS resources are private and SG-restricted so only the EKS worker SG can initiate traffic to these ports.

## Architecture Diagram

```mermaid
graph LR
  WAF[AWS WAF] --> CF[CloudFront]
  CF --> NLB[AWS NLB (ingress-nginx Service)]
  NLB --> NGINX[NGINX Ingress Controller]
  NGINX --> LMS[LMS Pod]
  NGINX --> CMS[CMS Pod]
  NGINX --> MFE[MFE Pod]

  LMS --> RDS[(RDS MySQL)]
  LMS --> MONGO[(MongoDB EC2)]
  LMS --> REDIS[(Redis EC2)]
  LMS --> ES[(Elasticsearch EC2)]

  CMS --> RDS
  CMS --> MONGO
  CMS --> REDIS
  CMS --> ES

  LMS --> MEDIA[(EFS RWX media PVC)]
  CMS --> MEDIA

  MEILI[Meilisearch Pod] --> EBS[(EBS gp3 PVC)]
```

## Network Flow Diagram

```mermaid
graph TD
  User[User] --> WAF[AWS WAF]
  WAF --> CF[CloudFront]
  CF --> NLB[AWS NLB (LoadBalancer)]
  NLB --> NGINX[NGINX Ingress]
  NGINX --> LMS[LMS Service]
  NGINX --> CMS[CMS Service]

  subgraph Private Subnets
    LMS --> RDS[(RDS MySQL)]
    LMS --> MONGO[(MongoDB EC2)]
    LMS --> REDIS[(Redis EC2)]
    LMS --> ES[(Elasticsearch EC2)]
  end

  LMS --> MEDIA[(EFS RWX media PVC)]
  CMS --> MEDIA

  MEILI[Meilisearch] --> EBS[(EBS gp3 PVC)]
```

## Notes (Assessment vs Real Production)

- CloudFront default domain (e.g. `d123.cloudfront.net`) does not match the Ingress host rules (`lms.openedx.local`, `studio.openedx.local`), so a default request can return 404. WAF proof uses a header-based block rule (403) which is independent of host routing.
- For real production you would use real DNS + ACM certificates, and configure CloudFront alternate domain names that match the Ingress hosts.
