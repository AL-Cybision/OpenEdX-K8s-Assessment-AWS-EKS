# Smoke Test (Operator Verification)

This document is for **operator-level verification** of the deployed platform and its architecture components.
It is not required for the assessment evidence pack, but it is the fastest way to confirm the stack is healthy.

## 1) Workload Health

```bash
kubectl -n openedx-prod get pods -o wide
kubectl -n openedx-prod get ingress -o wide
kubectl -n ingress-nginx get svc ingress-nginx-controller -o wide
kubectl -n openedx-prod get hpa
```

## 2) HTTP Health Checks

Placeholder ingress (requires `/etc/hosts` mapping as per `docs/reproduce.md`):
```bash
curl -kIs https://lms.openedx.local/heartbeat | head
curl -kIs https://studio.openedx.local/heartbeat | head
```

Real domain ingress (if configured):
```bash
curl -Is https://lms.example.com/heartbeat | head
curl -Is https://studio.example.com/heartbeat | head
```

## 3) Create Accounts (Admin + Staff)

Create admin (superuser) + staff and set password:
```bash
kubectl -n openedx-prod exec -it deploy/lms -c lms -- sh -lc '
  cd /openedx/edx-platform &&
  /openedx/venv/bin/python manage.py lms manage_user --superuser --staff admin admin@example.com &&
  /openedx/venv/bin/python manage.py lms changepassword admin
'
```

Create a course author (staff) and set password:
```bash
kubectl -n openedx-prod exec -it deploy/lms -c lms -- sh -lc '
  cd /openedx/edx-platform &&
  /openedx/venv/bin/python manage.py lms manage_user --staff courseauthor courseauthor@example.com &&
  /openedx/venv/bin/python manage.py lms changepassword courseauthor
'
```

## 4) Create a Course (Studio / CMS)

Terminal-only course creation:
```bash
kubectl -n openedx-prod exec deploy/cms -c cms -- sh -lc '
  cd /openedx/edx-platform &&
  /openedx/venv/bin/python manage.py cms create_course split admin@example.com SYNC SMOKE101 2026_T1 "Smoke Test Course" 2026-02-15
'
```

Confirm the course is visible to the modulestore:
```bash
kubectl -n openedx-prod exec deploy/lms -c lms -- sh -lc '
  cd /openedx/edx-platform &&
  /openedx/venv/bin/python manage.py lms dump_course_ids 2>/dev/null | grep -F "course-v1:SYNC+SMOKE101+2026_T1"
'
```

## 5) Enroll Learner (LMS)

```bash
kubectl -n openedx-prod exec deploy/lms -c lms -- sh -lc '
  cd /openedx/edx-platform &&
  /openedx/venv/bin/python manage.py lms enroll_user_in_course \
    -e learner1@example.com \
    -c course-v1:SYNC+SMOKE101+2026_T1
'
```

## 6) Persistence Check

Restart pods and confirm the course still exists:
```bash
kubectl -n openedx-prod rollout restart deploy/lms deploy/cms
kubectl -n openedx-prod rollout status deploy/lms --timeout=10m
kubectl -n openedx-prod rollout status deploy/cms --timeout=10m

kubectl -n openedx-prod exec deploy/lms -c lms -- sh -lc '
  cd /openedx/edx-platform &&
  /openedx/venv/bin/python manage.py lms dump_course_ids 2>/dev/null | grep -F "course-v1:SYNC+SMOKE101+2026_T1"
'
```

## 7) Cache Verification (Redis)

This verifies LMS can read/write to the configured cache backend:
```bash
kubectl -n openedx-prod exec deploy/lms -c lms -- sh -lc '
  cd /openedx/edx-platform &&
  /openedx/venv/bin/python manage.py lms shell -c "
from django.core.cache import caches
c=caches[\"default\"]
c.set(\"smoke:cache:test\", \"ok\", timeout=60)
print(c.get(\"smoke:cache:test\"))
"
'
```

Expected output includes: `ok`

## 8) CloudFront + WAF Verification

```bash
infra/cloudfront-waf/verify.sh
```

## 9) Observability Sanity

```bash
kubectl -n observability get pods
```

