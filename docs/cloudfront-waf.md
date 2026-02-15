# CloudFront + WAF (In front of NGINX Ingress)

## Terraform Apply

```bash
infra/cloudfront-waf/apply.sh
```

Rerun behavior:
- If CloudFront/WAF already exist in the account but local Terraform state is missing, `apply.sh` auto-imports them before planning/applying.
- This prevents `WAFDuplicateItemException` during assessor reruns in reused environments.

Origin protocol note:
- This repo uses `origin_protocol_policy = "http-only"` (CloudFront -> origin over HTTP).
- Reason: HTTPS-to-origin requires a publicly trusted certificate that matches the **origin hostname** CloudFront connects to. By default, this repo uses the ingress LoadBalancer DNS name as the origin, which is not covered by the app TLS certificate.
- TLS termination at NGINX is demonstrated via direct ingress access to `https://<LMS_HOST>` / `https://<CMS_HOST>` (production-mode: Let’s Encrypt via cert-manager; assessment-mode: self-signed).
- Production hardening: set the CloudFront origin domain name to a real DNS name covered by your certificate (for example `lms.<domain>` pointing to the ingress LoadBalancer), then switch CloudFront to HTTPS-to-origin.

`infra/cloudfront-waf/apply.sh` supports protocol selection:
```bash
# assessment-mode default
infra/cloudfront-waf/apply.sh

# hardened mode (requires trusted cert on origin)
ORIGIN_PROTOCOL_POLICY=https-only infra/cloudfront-waf/apply.sh
```

Outputs (captured):

```text
cloudfront_domain_name = "d1ga10o8eeu7yf.cloudfront.net"
waf_web_acl_arn = "arn:aws:wafv2:us-east-1:096365818004:global/webacl/openedx-prod-cf-waf/de51d17d-9baa-4504-a4e2-c53534fef7f0"
```

## Verification (WAF Block)

```bash
infra/cloudfront-waf/verify.sh
```

Captured result:

```text
Expected non-403 (no WAF block):
HTTP/2 404

Expected 403 (WAF block):
HTTP/2 403
```

Note: 404 for the default CloudFront domain is expected because it doesn't match the NGINX Ingress host rules (`LMS_HOST`, `CMS_HOST`). In production, attach a real domain to CloudFront + Ingress (alternate domain names) and align host routing.
