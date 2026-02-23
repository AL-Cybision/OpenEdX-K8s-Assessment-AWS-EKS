# Live Demo Checklist

Run this 15-30 minutes before the review call.

## 1) Demo Gate

```bash
cp -n configs/demo/demo.env.example .env.demo.local
# edit .env.demo.local with real credentials/passwords

scripts/openedxctl demo-gate
```

Optional fast path:

```bash
scripts/openedxctl demo-gate --skip-backup
```

Readonly evidence-only run:

```bash
scripts/openedxctl demo-gate --readonly --skip-hpa --skip-backup
```

Artifacts are written to:

```text
artifacts/demo-gate/<UTC_TS>/
```

Use:
- `summary.md`
- `json-summary.json`
- `raw.log`

## 2) Browser Endpoints

- `https://lms.<domain>`
- `https://studio.<domain>`
- `https://apps.lms.<domain>/authn/login`

## 3) Accounts

Use the emails from `.env.demo.local`:
- Admin: LMS + `/admin`
- Creator: Studio authoring
- Learner: LMS enrollment/dashboard

## 4) Live Actions They May Ask

### Create a course
- Sign in Studio as creator.
- Create or open demo course.

### Restart pods and show persistence
```bash
kubectl -n openedx-prod delete pod $(kubectl -n openedx-prod get pods --no-headers | awk '/^lms-.*Running/{print $1;exit}')
kubectl -n openedx-prod delete pod $(kubectl -n openedx-prod get pods --no-headers | awk '/^cms-.*Running/{print $1;exit}')
kubectl -n openedx-prod rollout status deploy/lms --timeout=600s
kubectl -n openedx-prod rollout status deploy/cms --timeout=600s
```

### Show HPA behavior
```bash
kubectl -n openedx-prod get hpa
kubectl -n openedx-prod get hpa -w
```

### Show backup evidence
```bash
scripts/60-backup-run.sh
```

### Show CloudFront/WAF behavior
```bash
scripts/53-cloudfront-waf-verify.sh
```
