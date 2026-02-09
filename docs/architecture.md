# Architecture & Network Flow

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
