# CloudFront + WAF (In front of NGINX Ingress)

## Terraform Apply

```bash
infra/cloudfront-waf/apply.sh
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

Note: 404 for the default CloudFront domain is expected because it doesn't match the NGINX Ingress host rules (`lms.openedx.local`, `studio.openedx.local`). In production, attach a real domain to CloudFront + Tutor/Ingress.
