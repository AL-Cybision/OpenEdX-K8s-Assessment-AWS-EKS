#!/usr/bin/env bash
set -euo pipefail

# Deterministic Open edX DB/app init flow for this repo's "external DB + no edge
# Caddy" architecture. We intentionally avoid `tutor k8s init` because that path
# may still execute Meilisearch bootstrap jobs even when RUN_MEILISEARCH=false.

NAMESPACE="${NAMESPACE:-openedx-prod}"
CMS_HOST="${CMS_HOST:-}"

kubectl -n "${NAMESPACE}" rollout status deploy/lms-worker --timeout=600s
kubectl -n "${NAMESPACE}" rollout status deploy/cms-worker --timeout=600s

LMS_WORKER_POD="$(kubectl -n "${NAMESPACE}" get pods -o name | rg '^pod/lms-worker-' | head -n1 | cut -d/ -f2)"
CMS_WORKER_POD="$(kubectl -n "${NAMESPACE}" get pods -o name | rg '^pod/cms-worker-' | head -n1 | cut -d/ -f2)"

if [[ -z "${LMS_WORKER_POD}" || -z "${CMS_WORKER_POD}" ]]; then
  echo "Unable to find lms-worker/cms-worker pods for migration init." >&2
  exit 1
fi

# Apply database schema for both services.
kubectl -n "${NAMESPACE}" exec "${CMS_WORKER_POD}" -c cms-worker -- sh -lc \
  'cd /openedx/edx-platform && /openedx/venv/bin/python manage.py cms migrate --noinput'

kubectl -n "${NAMESPACE}" exec "${LMS_WORKER_POD}" -c lms-worker -- sh -lc \
  'cd /openedx/edx-platform && /openedx/venv/bin/python manage.py lms migrate --noinput'

# Ensure Studio SSO works deterministically after fresh deploy:
# - `cms-sso` OAuth client exists in LMS
# - redirect URI matches current CMS host
# - ApplicationAccess scopes include user_id/profile/email used by Studio callback
if [[ -n "${CMS_HOST}" ]]; then
  kubectl -n "${NAMESPACE}" exec "${LMS_WORKER_POD}" -c lms-worker -- sh -lc "
    cd /openedx/edx-platform && cat >/tmp/bootstrap_cms_sso.py <<'PY'
from pathlib import Path
import re
from django.contrib.auth import get_user_model
from oauth2_provider.models import Application
from openedx.core.djangoapps.oauth_dispatch.models import ApplicationAccess

cms_host = \"${CMS_HOST}\"
redirect_uri = f\"https://{cms_host}/complete/edx-oauth2/\"
client_id = \"cms-sso\"

def read_cms_oauth_secret():
    cms_settings = Path('/openedx/edx-platform/cms/envs/tutor/production.py')
    if not cms_settings.exists():
        return None
    m = re.search(r'SOCIAL_AUTH_EDX_OAUTH2_SECRET\\s*=\\s*\\\"([^\\\"]+)\\\"', cms_settings.read_text())
    return m.group(1) if m else None

User = get_user_model()
owner = User.objects.filter(is_superuser=True).order_by('id').first() or User.objects.order_by('id').first()
if not owner:
    raise SystemExit('No user exists in LMS DB to own cms-sso oauth application')

app = Application.objects.filter(client_id=client_id).first()
if app is None:
    secret = read_cms_oauth_secret()
    if not secret:
        raise SystemExit('cms-sso missing and CMS OAuth secret not found in cms settings')
    app = Application.objects.create(
        client_id=client_id,
        client_secret=secret,
        user=owner,
        name='CMS SSO',
        client_type=Application.CLIENT_CONFIDENTIAL,
        authorization_grant_type=Application.GRANT_AUTHORIZATION_CODE,
        redirect_uris=redirect_uri,
        skip_authorization=True,
    )
    print('created oauth app', app.client_id)
else:
    app.user = owner
    app.name = 'CMS SSO'
    app.client_type = Application.CLIENT_CONFIDENTIAL
    app.authorization_grant_type = Application.GRANT_AUTHORIZATION_CODE
    app.redirect_uris = redirect_uri
    if hasattr(app, 'skip_authorization'):
        app.skip_authorization = True
    app.save()
    print('updated oauth app', app.client_id)

required_scopes = ['user_id', 'profile', 'email', 'read', 'write']
access, created = ApplicationAccess.objects.get_or_create(
    application=app,
    defaults={'scopes': required_scopes, 'filters': []},
)
access.scopes = required_scopes
if access.filters is None:
    access.filters = []
access.save()
print('created access' if created else 'updated access', access.scopes)
PY
    /openedx/venv/bin/python manage.py lms shell < /tmp/bootstrap_cms_sso.py
  "
else
  echo "CMS_HOST not set; skipping cms-sso oauth bootstrap." >&2
fi

# Restart web deployments to pick up a fully initialized schema.
kubectl -n "${NAMESPACE}" rollout restart deploy/lms deploy/cms
kubectl -n "${NAMESPACE}" rollout status deploy/lms --timeout=600s
kubectl -n "${NAMESPACE}" rollout status deploy/cms --timeout=600s

echo "Open edX init complete (migrations + web rollout)."
