# Screenshot Checklist (Minimum Set)

Place screenshots in this folder using these exact filenames:

1. `eks-cluster-active.png` — EKS cluster overview page for `openedx-eks` (Status: ACTIVE)
2. `openedx-pods.png` — `kubectl -n openedx-prod get pods`
3. `openedx-ingress.png` — `kubectl -n openedx-prod get ingress openedx`
4. `mfe-service-clusterip.png` — `kubectl -n openedx-prod get svc mfe -o wide` (type `ClusterIP`)
5. `OpenEdxLMS.png` — Browser: LMS UI loads (Welcome to My Open edX)
6. `studio-course-created.png` — Studio UI with created course visible
7. `mongo-course-persistence.png` — `kubectl -n openedx-prod exec deploy/lms -- python manage.py ...` showing course/modulestore-related collections (no secrets printed)
8. `course-persistence-after-restart.png` — Same course visible after LMS/CMS restart
9. `rds-private-endpoint.png` — RDS instance details showing endpoint + private networking / not public
10. `ec2-private-ips.png` — EC2 instances (mongo/redis/es) showing private IPs, no public IPv4
11. `hpa-scaling.png` — `kubectl -n openedx-prod get hpa` showing LMS at 6 replicas
12. `grafana-dashboard.png` — Grafana dashboard (CPU/memory/time series for openedx-prod)
13. `loki-logs.png` — Grafana Explore (Loki) showing a LogQL graph derived from `lms` logs (top paths)
14. `cloudfront-details.png` — CloudFront distribution details page
15. `waf-webacl.png` — WAF WebACL + rule page
16. `waf-block-403.png` — Terminal: `curl` showing HTTP/2 403 with `X-Block-Me: 1`

Optional:
- `hpa-scale-watch.png` — `kubectl -n openedx-prod get deploy lms -w`
