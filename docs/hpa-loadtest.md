# HPA + Load Test Evidence

## HPA Manifests
- `infra/k8s/05-hpa/lms-hpa.yaml`
- `infra/k8s/05-hpa/cms-hpa.yaml`

Apply:

```bash
infra/k8s/05-hpa/apply.sh
```

Notes:
- `infra/k8s/05-hpa/apply.sh` requires `metrics-server` (`kubectl top nodes` must work).
- Default resource requests are tuned for reproducibility on `2 x t3.large`.
- If rollout is capacity-constrained, temporarily scale nodegroup desired size to `3` before running k6.

## k6 Load Test (in-cluster)

Script:
- `infra/k8s/05-hpa/loadtest-k6.js`

Run:

```bash
kubectl -n openedx-prod create configmap k6-script \
  --from-file=loadtest-k6.js=infra/k8s/05-hpa/loadtest-k6.js \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n openedx-prod delete job k6-loadtest --ignore-not-found

cat <<'YAML' | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: k6-loadtest
  namespace: openedx-prod
spec:
  backoffLimit: 0
  ttlSecondsAfterFinished: 600
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: k6
          image: grafana/k6:0.49.0
          args: ["run", "--vus", "120", "--duration", "5m", "/scripts/loadtest-k6.js"]
          volumeMounts:
            - name: scripts
              mountPath: /scripts
      volumes:
        - name: scripts
          configMap:
            name: k6-script
YAML

kubectl -n openedx-prod logs -f job/k6-loadtest
```

## HPA Result (Captured)

```text
NAME      REFERENCE        TARGETS         MINPODS   MAXPODS   REPLICAS   AGE
cms-hpa   Deployment/cms   cpu: 0%/70%     2         6         2          7m12s
lms-hpa   Deployment/lms   cpu: 297%/70%   2         6         6          7m27s
```

This confirms LMS scaled from 2 to 6 replicas under load.
