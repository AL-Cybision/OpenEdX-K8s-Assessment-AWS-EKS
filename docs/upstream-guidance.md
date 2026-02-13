# Upstream Guidance (Research Summary) and How This Repo Applies It

This repo is tailored for the **Al Nafi Open edX on AWS EKS assessment** (AWS-only, EKS-only, external data services, NGINX ingress, CloudFront+WAF proof). The goal of this document is to:

- Identify the **most authoritative upstream guides** for Open edX operations in 2026.
- Capture the **key production rules** they imply (proxy/TLS/cookies/versioning).
- Explain **how this repo implements them**, and where we intentionally diverge due to assessment constraints.

## 1) What Is “The Best Guide” for Open edX?

For real operations, the strongest source-of-truth ordering is:

1. **Tutor documentation** (operator manual) for install/config/Kubernetes/proxy/scale.
2. **Open edX official docs** for platform overview, release notes, and operator expectations.
3. **Open edX Proposals (OEPs)** for architecture direction (containers + operator-managed config).
4. **AWS/Kubernetes upstream docs** for infrastructure primitives (EKS add-ons, ingress patterns, storage).
5. **High-signal Discuss threads** for edge cases and “known foot-guns” (redirect loops, cookie scope, MFE auth).

The repo keeps these links in `docs/references.md`.

## 2) Key Upstream Rules That Matter in Production

### A) Versioning: pick a named Open edX release and match Tutor major

- Open edX releases (named) map to Tutor major versions.
- This repo uses Tutor v21 (Open edX Ulmo) and calls out the mapping in `docs/references.md`.

### B) Proxy/TLS: if TLS terminates at a reverse proxy, Open edX must behave as HTTPS behind it

Production issue pattern:
- The reverse proxy terminates TLS (browser sees HTTPS).
- Upstream apps (LMS/CMS/MFEs) see plain HTTP internally.
- If `ENABLE_HTTPS`/forwarded headers/cookie security are wrong, you get:
  - redirect loops
  - mixed-content/CORS issues in MFEs
  - broken login/register flows

How this repo applies it:
- TLS terminates at **NGINX Ingress** (required by assignment).
- Tutor is forced to behave as HTTPS behind a proxy (`ENABLE_HTTPS=true`).
- Cookie scope is explicitly configured when using real subdomains (so sessions are consistent across `lms.*`, `studio.*`, `apps.*`).

### C) Cookie scope for subdomains: set cookie domains intentionally

If LMS/Studio live on subdomains, cookie scoping mistakes can cause login/session loops.

How this repo applies it:
- The `openedx-mfe-https` Tutor plugin sets `SESSION_COOKIE_DOMAIN` and `CSRF_COOKIE_DOMAIN` to the parent domain when using real DNS.

### D) Kubernetes: storage and metrics are not optional for “production-ish”

The practical minimum for this assessment stack:
- **EBS CSI driver** installed (for default dynamic storage and Meilisearch PVC).
- A default StorageClass set (we use `gp3`).
- **metrics-server** installed (HPA needs CPU metrics).
- RWX shared media for LMS/CMS (we use EFS RWX to satisfy “shared PVC” and multi-replica LMS/CMS).

## 3) Where We Intentionally Diverge (Assessment Constraints)

Tutor’s default Kubernetes approach uses its own proxy stack. The assignment mandates:

- Edge proxy is **NGINX** (Ingress Controller), not Tutor’s default Caddy.
- Data layer is offloaded outside the cluster (RDS MySQL + EC2 Mongo/Redis/Elasticsearch).

So this repo:
- Uses Tutor to render k8s manifests, then applies them through a post-render filter that removes edge Caddy resources.
- Injects production-style probes and shared media mounts at apply time.

## 4) How to Use This Repo (Practical “Best Guide” Path)

Use the repo runbook as the executable guide:
- `docs/reproduce.md` (assessor-friendly, script-driven)

Use upstream docs as “why/how deeper” references:
- `docs/references.md`

If you hit redirect/auth/MFE issues:
- Start with the Tutor “behind a proxy” guide.
- Then review the Discuss threads linked in `docs/references.md`.

