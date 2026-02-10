# Screenshot Checklist (Minimum Set)

Place screenshots in this folder using these exact filenames:

1. `eks-cluster-active.png` — EKS cluster overview page for `openedx-eks` (Status: ACTIVE)
2. `openedx-pods.png` — `kubectl -n openedx-prod get pods`
3. `openedx-ingress.png` — `kubectl -n openedx-prod get ingress openedx`
4. `rds-private-endpoint.png` — RDS instance details showing endpoint + private networking / not public
5. `ec2-private-ips.png` — EC2 instances (mongo/redis/es) showing private IPs, no public IPv4
6. `hpa-scaling.png` — `kubectl -n openedx-prod get hpa` showing LMS at 6 replicas
7. `grafana-dashboard.png` — Grafana dashboard (CPU/memory/time series for openedx-prod)
8. `loki-logs.png` — Grafana Explore (Loki) showing a LogQL graph derived from `lms` logs (top paths)
9. `cloudfront-details.png` — CloudFront distribution details page
10. `waf-webacl.png` — WAF WebACL + rule page
11. `waf-block-403.png` — Terminal: `curl` showing HTTP/2 403 with `X-Block-Me: 1`

Optional:
- `hpa-scale-watch.png` — `kubectl -n openedx-prod get deploy lms -w`
