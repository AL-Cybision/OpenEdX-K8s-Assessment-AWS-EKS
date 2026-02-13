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

# Keep host-level URLs aligned with HTTPS ingress hostnames.
LMS_ROOT_URL = "https://{{ LMS_HOST }}"
CMS_ROOT_URL = "https://{{ CMS_HOST }}"

# The learner-dashboard MFE in the stock Tutor MFE image may lack reliable runtime
# config injection when using placeholder local domains. Disable redirect-to-MFE
# to avoid /dashboard <-> /learner-dashboard loops and keep the classic dashboard.
LEARNER_HOME_MFE_REDIRECT_PERCENTAGE = 0

# The AuthN MFE (apps.{{ LMS_HOST }}/authn/*) can be fragile in "assessment/staging"
# environments and may trigger browser redirect loops. Keep the classic LMS login/register.
FEATURES['ENABLE_AUTHN_MICROFRONTEND'] = False

# Force MFE config API URLs to use HTTPS to avoid mixed-content browser blocks.
def _openedx_force_https(url):
    if not isinstance(url, str):
        return url
    # Keep API paths as-is (for example "/csrf/api/v1/token").
    if url.startswith("/"):
        return url
    if url.startswith("http://"):
        return "https://" + url[len("http://"):]
    if url.startswith("https://"):
        return url
    # Some Tutor defaults are hostnames without scheme (for example BASE_URL).
    # Normalize those to absolute HTTPS URLs to avoid frontend runtime issues.
    if url:
        return "https://" + url.lstrip("/")
    return url

# MFE_CONFIG should exist in LMS settings, but guard to avoid breaking startup if
# upstream changes.
if "MFE_CONFIG" in globals():
    if not MFE_CONFIG.get("BASE_URL"):
        MFE_CONFIG["BASE_URL"] = "apps.{{ LMS_HOST }}"
    # Empty CREDENTIALS_BASE_URL can lead to broken MFE API calls.
    if not MFE_CONFIG.get("CREDENTIALS_BASE_URL"):
        MFE_CONFIG["CREDENTIALS_BASE_URL"] = "https://{{ LMS_HOST }}"
    # Provide explicit defaults expected by Indigo MFEs to avoid blank screens
    # due to missing config keys.
    if not MFE_CONFIG.get("SUPPORT_EMAIL"):
        MFE_CONFIG["SUPPORT_EMAIL"] = CONTACT_EMAIL
    if not MFE_CONFIG.get("TERMS_OF_SERVICE_URL"):
        MFE_CONFIG["TERMS_OF_SERVICE_URL"] = "https://{{ LMS_HOST }}/tos"
    if not MFE_CONFIG.get("PRIVACY_POLICY_URL"):
        MFE_CONFIG["PRIVACY_POLICY_URL"] = "https://{{ LMS_HOST }}/privacy"
    if not MFE_CONFIG.get("CREDIT_PURCHASE_URL"):
        MFE_CONFIG["CREDIT_PURCHASE_URL"] = "https://{{ LMS_HOST }}/dashboard"
    if not MFE_CONFIG.get("ORDER_HISTORY_URL"):
        MFE_CONFIG["ORDER_HISTORY_URL"] = "https://{{ LMS_HOST }}/dashboard"
    if "ENABLE_ACCESSIBILITY_PAGE" not in MFE_CONFIG:
        MFE_CONFIG["ENABLE_ACCESSIBILITY_PAGE"] = False
    for _k, _v in list(MFE_CONFIG.items()):
        # Only normalize known URL-like keys and endpoint URLs.
        if (
            _k == "BASE_URL"
            or _k.endswith("_URL")
            or _k.endswith("_BASE_URL")
            or _k.endswith("_ENDPOINT")
        ):
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
