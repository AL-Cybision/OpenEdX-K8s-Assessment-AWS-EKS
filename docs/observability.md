# Observability Stack (Prometheus/Grafana + Loki)

This installs:
- `kube-prometheus-stack` (Prometheus Operator, Prometheus, Alertmanager, Grafana)
- `loki-stack` (Loki + Promtail)

## Install

```bash
infra/observability/install.sh
```

## Verify

```bash
kubectl -n observability get pods
helm -n observability ls
```

## Access Grafana

```bash
# Get admin password (do not screenshot this output).
kubectl -n observability get secret kube-prometheus-stack-grafana \
  -o jsonpath="{.data.admin-password}" | base64 -d ; echo

kubectl -n observability port-forward svc/kube-prometheus-stack-grafana 3000:80
```

Then open `http://localhost:3000` and log in as `admin`.

## Loki Datasource

Loki datasource is auto-provisioned in Grafana via `infra/observability/values-kube-prometheus-stack.yaml`.

Loki service (ClusterIP) is:

```bash
kubectl -n observability get svc loki-stack -o wide
```

## Evidence Screenshots

Dashboard screenshot:
- Grafana: `Dashboards` -> search `Kubernetes / Compute Resources / Namespace (Pods)` -> set `namespace=openedx-prod`

Logs screenshot:
- Grafana: `Explore` -> datasource `Loki`
- Query (graph, from `lms` logs): `topk(5, sum by (path) (rate({namespace="openedx-prod", pod=~"lms-.*"} | regexp "GET (?P<path>/[^ ]*)"[5m])))`
- Raw logs query (optional): `{namespace="openedx-prod", pod=~"lms-.*"}`
- If Explore shows `React Monaco Editor failed to load`, switch from `Code` to `Builder`.

## Alerting Configuration

Alertmanager:
- Enabled via `infra/observability/values-kube-prometheus-stack.yaml` (`alertmanager.enabled: true`)

Custom Prometheus alerts for `openedx-prod`:
- `infra/observability/openedx-prometheusrule.yaml`

Apply:
```bash
infra/observability/apply-alerts.sh
```

Verify:
```bash
kubectl -n observability get prometheusrule openedx-prod-rules -o yaml | head -n 80
kubectl -n observability get --raw \"/api/v1/namespaces/observability/services/kube-prometheus-stack-prometheus:9090/proxy/api/v1/rules\" | jq '.data.groups[] | select(.name|test(\"openedx\"))'
```
