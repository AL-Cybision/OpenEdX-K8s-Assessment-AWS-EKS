# Configuration Decisions & Rationale

- **EKS (AWS only)**: Required by assessment and production-grade managed control plane.
- **Tutor v21**: Latest stable Tutor release; includes k8s commands built-in.
- **External DBs**: RDS for MySQL; EC2 for Mongo/Redis/Elasticsearch to meet requirement of external data layer.
- **NGINX Ingress**: Replaces Caddy; industry standard, supports TLS termination and HTTP/2.
- **CloudFront + WAF**: Required security/performance layer; WAF rules verified via 403 block.
- **Storage**: EFS (RWX) for shared Open edX uploads/media; EBS CSI gp3 for single-writer PVCs (Meilisearch).
- **Observability**: kube-prometheus-stack + Loki for metrics and logs with minimal config.
- **Cost control**: Small instance sizes (t3.micro/t3.small) and short retention.
