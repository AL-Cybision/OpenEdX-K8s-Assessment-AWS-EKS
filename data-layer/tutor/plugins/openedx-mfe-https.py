from __future__ import annotations

from tutor import hooks

# When TLS terminates at the NGINX Ingress (not Tutor's Caddy proxy), MFEs are
# served over HTTPS. The upstream Open edX default adds only HTTP origins to
# the CORS/CSRF allow-lists and also publishes HTTP base URLs via the MFE config
# API. Modern browsers block those HTTP XHR/fetch calls from an HTTPS origin
# (mixed content), which breaks AuthN/Authoring MFEs in the browser.

LMS_PATCH = """\
# Allow MFEs served over HTTPS (TLS terminated at NGINX Ingress).
CORS_ORIGIN_WHITELIST.append("https://apps.{{ LMS_HOST }}")
CSRF_TRUSTED_ORIGINS.append("https://apps.{{ LMS_HOST }}")

# Force MFE config API URLs to use HTTPS to avoid mixed-content browser blocks.
def _openedx_force_https(url):
    if isinstance(url, str) and url.startswith("http://"):
        return "https://" + url[len("http://"):]
    return url

# MFE_CONFIG should exist in LMS settings, but guard to avoid breaking startup if
# upstream changes.
if "MFE_CONFIG" in globals():
    for _k, _v in list(MFE_CONFIG.items()):
        MFE_CONFIG[_k] = _openedx_force_https(_v)

# These variables exist on recent Open edX versions, but guard for safety.
for _name in (
    "AUTHN_MICROFRONTEND_URL",
    "ACCOUNT_MICROFRONTEND_URL",
    "DISCUSSIONS_MICROFRONTEND_URL",
    "LEARNING_MICROFRONTEND_URL",
    "ADMIN_CONSOLE_MICROFRONTEND_URL",
):
    if _name in globals():
        globals()[_name] = _openedx_force_https(globals()[_name])
"""

CMS_PATCH = """\
# Allow MFEs served over HTTPS (TLS terminated at NGINX Ingress).
CORS_ORIGIN_WHITELIST.append("https://apps.{{ LMS_HOST }}")
CSRF_TRUSTED_ORIGINS.append("https://apps.{{ LMS_HOST }}")

# Force MFE-related URLs to use HTTPS to avoid mixed-content browser blocks.
def _openedx_force_https(url):
    if isinstance(url, str) and url.startswith("http://"):
        return "https://" + url[len("http://"):]
    return url

if "MFE_CONFIG" in globals():
    for _k, _v in list(MFE_CONFIG.items()):
        MFE_CONFIG[_k] = _openedx_force_https(_v)

if "COURSE_AUTHORING_MICROFRONTEND_URL" in globals():
    COURSE_AUTHORING_MICROFRONTEND_URL = _openedx_force_https(COURSE_AUTHORING_MICROFRONTEND_URL)
"""

hooks.Filters.ENV_PATCHES.add_item(("openedx-lms-production-settings", LMS_PATCH))
hooks.Filters.ENV_PATCHES.add_item(("openedx-cms-production-settings", CMS_PATCH))
