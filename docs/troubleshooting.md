# Troubleshooting Guide

## Meilisearch PVC Pending
- Cause: No default StorageClass.
- Fix:
```bash
kubectl get storageclass
kubectl get storageclass gp2 >/dev/null 2>&1 && \
  kubectl patch storageclass gp2 -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
kubectl patch storageclass gp3 -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
kubectl -n openedx-prod delete pvc meilisearch
infra/k8s/04-tutor-apply/apply.sh
```

## LMS/CMS Workers CrashLoop (Redis password)
- Cause: Redis password contains special chars (needs URL encoding), or Tutor doesn't include auth in rendered URLs unless a username is set.
- Fix:
  - URL‑encode the Redis password before saving Tutor config.
  - Set `REDIS_USERNAME=default` (Redis ACL default user + `requirepass`).

## Elasticsearch fails to start
- Cause: `vm.max_map_count` not set or incorrect data/log paths.
- Fix: Ensure `vm.max_map_count=262144` and data/log paths are writable (handled in user-data).

## Caddy reappears after `tutor k8s start`
- Fix: Always use `infra/k8s/04-tutor-apply/apply.sh`.

## HPA not scaling
- Check metrics-server:
```bash
kubectl -n kube-system get deploy metrics-server
```
- Confirm CPU requests/limits set on LMS/CMS.

## CloudFront returns 404
- Cause: CloudFront default domain (e.g. `d123.cloudfront.net`) doesn't match the NGINX Ingress host rules (`lms.openedx.local`, `studio.openedx.local`), so NGINX returns 404/400.
- Fix (production): use a real domain and configure CloudFront alternate domain + certificate to match your Tutor/Ingress hosts.
