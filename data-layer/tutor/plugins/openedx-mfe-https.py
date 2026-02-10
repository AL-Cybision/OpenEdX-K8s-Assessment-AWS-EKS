from __future__ import annotations

from tutor import hooks

# When TLS terminates at the NGINX Ingress (not Tutor's Caddy proxy), MFEs are
# served over HTTPS. The upstream Open edX default adds only HTTP origins to
# the CORS/CSRF allow-lists, which breaks AuthN/Authoring MFEs in the browser.

LMS_PATCH = """\
# Allow MFEs served over HTTPS (TLS terminated at NGINX Ingress).
CORS_ORIGIN_WHITELIST.append("https://apps.{{ LMS_HOST }}")
CSRF_TRUSTED_ORIGINS.append("https://apps.{{ LMS_HOST }}")
"""

CMS_PATCH = """\
# Allow MFEs served over HTTPS (TLS terminated at NGINX Ingress).
CORS_ORIGIN_WHITELIST.append("https://apps.{{ LMS_HOST }}")
CSRF_TRUSTED_ORIGINS.append("https://apps.{{ LMS_HOST }}")
"""

hooks.Filters.ENV_PATCHES.add_item(("openedx-lms-production-settings", LMS_PATCH))
hooks.Filters.ENV_PATCHES.add_item(("openedx-cms-production-settings", CMS_PATCH))
