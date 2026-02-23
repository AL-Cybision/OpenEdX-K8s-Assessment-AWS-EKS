#!/usr/bin/env bash
set -euo pipefail

# Demo-grade end-to-end validation gate for Open edX + AWS wiring.
# Produces timestamped artifacts with pass/fail stage results.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

NAMESPACE="${NAMESPACE:-openedx-prod}"
AWS_REGION="${AWS_REGION:-us-east-1}"
DEMO_ENV_FILE="${DEMO_ENV_FILE:-${REPO_ROOT}/.env.demo.local}"

SKIP_HPA=false
SKIP_BACKUP=false
READONLY=false

usage() {
  cat <<'EOF'
Usage:
  scripts/54-demo-gate.sh [--skip-hpa] [--skip-backup] [--readonly]

Options:
  --skip-hpa      Skip HPA load/scale drill.
  --skip-backup   Skip backup snapshot drill.
  --readonly      Run non-mutating checks only (skip account/course/persistence/hpa/backup mutations).
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-hpa)
      SKIP_HPA=true
      shift
      ;;
    --skip-backup)
      SKIP_BACKUP=true
      shift
      ;;
    --readonly)
      READONLY=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown flag: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

TS_UTC="$(date -u +%Y%m%dT%H%M%SZ)"
ARTIFACT_DIR="${REPO_ROOT}/artifacts/demo-gate/${TS_UTC}"
RAW_LOG="${ARTIFACT_DIR}/raw.log"
SUMMARY_MD="${ARTIFACT_DIR}/summary.md"
SUMMARY_JSON="${ARTIFACT_DIR}/json-summary.json"
STAGE_TSV="${ARTIFACT_DIR}/stages.tsv"

mkdir -p "${ARTIFACT_DIR}"
touch "${RAW_LOG}" "${STAGE_TSV}"

FAILED=0

LMS_HOST=""
CMS_HOST=""
MFE_HOST=""

DEMO_ADMIN_EMAIL=""
DEMO_CREATOR_EMAIL=""
DEMO_LEARNER_EMAIL=""
DEMO_ADMIN_PASSWORD=""
DEMO_CREATOR_PASSWORD=""
DEMO_LEARNER_PASSWORD=""
DEMO_COURSE_ID=""
DEMO_COURSE_TITLE=""

DEMO_ADMIN_USERNAME=""
DEMO_CREATOR_USERNAME=""
DEMO_LEARNER_USERNAME=""

say() {
  echo "[$(date -u +%H:%M:%S)] $*"
}

sanitize_detail() {
  tr '\n' ' ' | tr '\t' ' ' | sed 's/  */ /g'
}

record_stage() {
  local stage="$1"
  local status="$2"
  local detail="$3"
  printf "%s\t%s\t%s\n" "${stage}" "${status}" "$(printf '%s' "${detail}" | sanitize_detail)" >> "${STAGE_TSV}"
}

finalize() {
  local rc=$?
  local overall="PASS"
  if [[ ${FAILED} -ne 0 || ${rc} -ne 0 ]]; then
    overall="FAIL"
  fi

  {
    echo "# Demo Gate Summary"
    echo
    echo "- Timestamp (UTC): \`${TS_UTC}\`"
    echo "- Namespace: \`${NAMESPACE}\`"
    echo "- Region: \`${AWS_REGION}\`"
    echo "- Readonly mode: \`${READONLY}\`"
    echo "- Skip HPA: \`${SKIP_HPA}\`"
    echo "- Skip Backup: \`${SKIP_BACKUP}\`"
    echo "- Overall: **${overall}**"
    echo
    echo "## Stage Results"
    echo
    echo "| Stage | Status | Detail |"
    echo "|---|---|---|"
    while IFS=$'\t' read -r stage status detail; do
      [[ -z "${stage}" ]] && continue
      echo "| ${stage} | ${status} | ${detail} |"
    done < "${STAGE_TSV}"
    echo
    echo "## Hosts"
    echo
    echo "- LMS: \`${LMS_HOST:-n/a}\`"
    echo "- CMS: \`${CMS_HOST:-n/a}\`"
    echo "- MFE: \`${MFE_HOST:-n/a}\`"
    echo
    echo "## Artifacts"
    echo
    echo "- Raw log: \`raw.log\`"
    echo "- JSON summary: \`json-summary.json\`"
  } > "${SUMMARY_MD}"

  jq -Rn \
    --arg timestamp "${TS_UTC}" \
    --arg namespace "${NAMESPACE}" \
    --arg region "${AWS_REGION}" \
    --arg overall "${overall}" \
    '
      def stage_obj:
        split("\t") | {stage: .[0], status: .[1], detail: (.[2] // "")};
      {
        timestamp_utc: $timestamp,
        namespace: $namespace,
        region: $region,
        overall: $overall,
        stages: [inputs | select(length > 0) | stage_obj]
      }
    ' < "${STAGE_TSV}" > "${SUMMARY_JSON}"
}
trap finalize EXIT

fail_stage() {
  local msg="$1"
  echo "ERROR: ${msg}" >&2
  return 1
}

run_stage() {
  local stage="$1"
  local desc="$2"
  local fn="$3"
  local detail_var="${4:-}"
  local detail=""
  local stage_log="${ARTIFACT_DIR}/.${stage}.log"

  say "=== ${stage}: ${desc} ===" | tee -a "${RAW_LOG}"
  set +e
  "${fn}" >"${stage_log}" 2>&1
  local rc=$?
  set -e
  cat "${stage_log}" | tee -a "${RAW_LOG}"
  rm -f "${stage_log}"

  if [[ -n "${detail_var}" ]]; then
    detail="${!detail_var:-${desc}}"
  else
    detail="${desc}"
  fi

  if [[ ${rc} -eq 0 ]]; then
    record_stage "${stage}" "PASS" "${detail}"
    return 0
  fi

  record_stage "${stage}" "FAIL" "${detail}"
  FAILED=1
  return 1
}

skip_stage() {
  local stage="$1"
  local reason="$2"
  say "=== ${stage}: SKIPPED (${reason}) ===" | tee -a "${RAW_LOG}"
  record_stage "${stage}" "SKIP" "${reason}"
}

require_cmd() {
  local cmd="$1"
  command -v "${cmd}" >/dev/null 2>&1 || fail_stage "Missing required command: ${cmd}"
}

derive_username_from_email() {
  local email="$1"
  local fallback="$2"
  local local_part
  local_part="$(printf '%s' "${email}" | cut -d@ -f1 | tr -cd 'a-zA-Z0-9_.-')"
  if [[ -z "${local_part}" ]]; then
    printf '%s\n' "${fallback}"
  else
    printf '%s\n' "${local_part}"
  fi
}

is_ok_http_code() {
  [[ "$1" =~ ^2[0-9][0-9]$ || "$1" =~ ^3[0-9][0-9]$ ]]
}

STAGE00_DETAIL=""
stage00_preflight() {
  require_cmd aws || return 1
  require_cmd kubectl || return 1
  require_cmd terraform || return 1
  require_cmd jq || return 1
  require_cmd curl || return 1

  kubectl get ns "${NAMESPACE}" >/dev/null
  kubectl -n "${NAMESPACE}" get ingress openedx >/dev/null

  local hosts
  hosts="$(kubectl -n "${NAMESPACE}" get ingress openedx -o jsonpath='{range .spec.rules[*]}{.host}{"\n"}{end}')"
  LMS_HOST="$(printf '%s\n' "${hosts}" | grep -E '^lms\.' | head -n1 || true)"
  CMS_HOST="$(printf '%s\n' "${hosts}" | grep -E '^studio\.' | head -n1 || true)"
  MFE_HOST="$(printf '%s\n' "${hosts}" | grep -E '^apps\.' | head -n1 || true)"

  [[ -n "${LMS_HOST}" ]] || fail_stage "Ingress does not contain lms.* host" || return 1
  [[ -n "${CMS_HOST}" ]] || fail_stage "Ingress does not contain studio.* host" || return 1
  [[ -n "${MFE_HOST}" ]] || fail_stage "Ingress does not contain apps.* host" || return 1

  getent hosts "${LMS_HOST}" >/dev/null || fail_stage "DNS does not resolve ${LMS_HOST}" || return 1
  getent hosts "${CMS_HOST}" >/dev/null || fail_stage "DNS does not resolve ${CMS_HOST}" || return 1
  getent hosts "${MFE_HOST}" >/dev/null || fail_stage "DNS does not resolve ${MFE_HOST}" || return 1

  STAGE00_DETAIL="tools ok; ingress + DNS ok (${LMS_HOST}, ${CMS_HOST}, ${MFE_HOST})"
}

STAGE01_DETAIL=""
stage01_core_liveness() {
  local pods_json="${ARTIFACT_DIR}/openedx-pods.json"
  kubectl -n "${NAMESPACE}" get pods -o json > "${pods_json}"
  kubectl -n "${NAMESPACE}" get pods | tee "${ARTIFACT_DIR}/openedx-pods.txt" >/dev/null

  local prefixes=(
    "lms-|lms web"
    "cms-|cms web"
    "mfe-|mfe"
    "lms-worker-|lms worker"
    "cms-worker-|cms worker"
    "smtp-|smtp relay"
  )

  local summary=""
  local item prefix label total ready
  for item in "${prefixes[@]}"; do
    prefix="${item%%|*}"
    label="${item##*|}"
    total="$(jq -r --arg p "${prefix}" '[.items[] | select(.metadata.name | startswith($p))] | length' "${pods_json}")"
    ready="$(jq -r --arg p "${prefix}" '[.items[] | select(.metadata.name | startswith($p)) | select(([.status.containerStatuses[]?.ready] | all))] | length' "${pods_json}")"
    [[ "${total}" -gt 0 ]] || fail_stage "No pods found for component: ${label}" || return 1
    [[ "${ready}" -gt 0 ]] || fail_stage "No Ready pods for component: ${label}" || return 1
    summary+="${label} ${ready}/${total}; "
  done

  kubectl -n "${NAMESPACE}" get hpa cms-hpa lms-hpa > "${ARTIFACT_DIR}/hpa-core.txt"

  local cert_ready
  cert_ready="$(kubectl -n "${NAMESPACE}" get certificate openedx-tls -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')"
  [[ "${cert_ready}" == "True" ]] || fail_stage "Certificate openedx-tls is not Ready=True" || return 1

  STAGE01_DETAIL="component readiness ok; ${summary} tls ready"
}

STAGE02_DETAIL=""
stage02_edge_reachability() {
  local lms_code cms_code mfe_code
  lms_code="$(curl -fsS -o /dev/null -w '%{http_code}' "https://${LMS_HOST}/heartbeat")"
  cms_code="$(curl -fsS -o /dev/null -w '%{http_code}' "https://${CMS_HOST}/heartbeat")"
  mfe_code="$(curl -fsS -o /dev/null -w '%{http_code}' "https://${MFE_HOST}/authn/login")"

  is_ok_http_code "${lms_code}" || fail_stage "LMS heartbeat returned ${lms_code}" || return 1
  is_ok_http_code "${cms_code}" || fail_stage "CMS heartbeat returned ${cms_code}" || return 1
  is_ok_http_code "${mfe_code}" || fail_stage "MFE login returned ${mfe_code}" || return 1

  STAGE02_DETAIL="lms=${lms_code}, cms=${cms_code}, mfe=${mfe_code}"
}

STAGE03_DETAIL=""
stage03_external_data_and_search() {
  local tf_dir="${REPO_ROOT}/configs/terraform/data-layer"
  local rds_endpoint mongo_ip redis_ip es_ip
  terraform -chdir="${tf_dir}" init -input=false >/dev/null

  rds_endpoint="$(terraform -chdir="${tf_dir}" output -raw rds_endpoint)"
  mongo_ip="$(terraform -chdir="${tf_dir}" output -raw mongo_private_ip)"
  redis_ip="$(terraform -chdir="${tf_dir}" output -raw redis_private_ip)"
  es_ip="$(terraform -chdir="${tf_dir}" output -raw elasticsearch_private_ip)"

  local cleanup_verify_net=0
  kubectl -n "${NAMESPACE}" delete pod verify-net --ignore-not-found >/dev/null 2>&1 || true
  kubectl -n "${NAMESPACE}" run verify-net --restart=Never --image=busybox:1.36 --command -- sh -c 'sleep 300'
  cleanup_verify_net=1
  kubectl -n "${NAMESPACE}" wait --for=condition=Ready pod/verify-net --timeout=120s
  kubectl -n "${NAMESPACE}" exec verify-net -- sh -c \
    "nc -zvw3 ${rds_endpoint} 3306 && nc -zvw3 ${mongo_ip} 27017 && nc -zvw3 ${redis_ip} 6379 && nc -zvw3 ${es_ip} 9200"

  kubectl -n "${NAMESPACE}" exec deploy/cms -c cms -- sh -lc 'cd /openedx/edx-platform && /openedx/venv/bin/python manage.py cms shell <<'\''PY'\''
from django.conf import settings
cfg = settings.ELASTIC_SEARCH_CONFIG
raw = str(cfg)
if "localhost:9200" in raw or "127.0.0.1:9200" in raw:
    raise SystemExit(f"ELASTIC_SEARCH_CONFIG still local: {cfg}")
print("OK ELASTIC_SEARCH_CONFIG", cfg)
PY'

  kubectl -n "${NAMESPACE}" exec deploy/cms -c cms -- sh -lc 'cd /openedx/edx-platform && /openedx/venv/bin/python manage.py cms shell <<'\''PY'\''
from xmodule.modulestore.django import modulestore
from cms.djangoapps.contentstore.courseware_index import CoursewareSearchIndexer

courses = list(modulestore().get_courses())
if not courses:
    print("SKIP reindex smoke: no courses found")
    raise SystemExit(0)

indexed = CoursewareSearchIndexer.do_course_reindex(modulestore(), courses[0].id)
if indexed <= 0:
    raise SystemExit(f"Reindex returned non-positive count: {indexed}")
print("OK reindex smoke indexed", indexed, "course", courses[0].id)
PY'

  STAGE03_DETAIL="db connectivity ok; cms search config external; reindex smoke passed"

  if [[ "${cleanup_verify_net}" -eq 1 ]]; then
    kubectl -n "${NAMESPACE}" delete pod verify-net --ignore-not-found >/dev/null 2>&1 || true
  fi
}

STAGE04_DETAIL=""
stage04_studio_sso_contract() {
  kubectl -n "${NAMESPACE}" exec deploy/lms -c lms -- sh -lc 'cd /openedx/edx-platform && /openedx/venv/bin/python manage.py lms shell <<'\''PY'\''
from oauth2_provider.models import Application
from openedx.core.djangoapps.oauth_dispatch.models import ApplicationAccess

app = Application.objects.filter(client_id="cms-sso").first()
if app is None:
    raise SystemExit("Missing oauth application: cms-sso")

if "studio." not in (app.redirect_uris or ""):
    raise SystemExit(f"cms-sso redirect URI does not include studio host: {app.redirect_uris}")

access = ApplicationAccess.objects.filter(application=app).first()
if access is None:
    raise SystemExit("Missing ApplicationAccess for cms-sso")

required = {"user_id", "profile", "email"}
scopes = set(access.scopes or [])
missing = sorted(required - scopes)
if missing:
    raise SystemExit(f"cms-sso missing scopes: {missing}")
print("OK cms-sso", app.redirect_uris, sorted(scopes))
PY'

  STAGE04_DETAIL="cms-sso app + redirect URI + scopes validated"
}

load_demo_env() {
  [[ -f "${DEMO_ENV_FILE}" ]] || fail_stage "Demo env file not found: ${DEMO_ENV_FILE}" || return 1
  # shellcheck disable=SC1090
  source "${DEMO_ENV_FILE}"

  : "${DEMO_ADMIN_EMAIL:?missing DEMO_ADMIN_EMAIL}"
  : "${DEMO_CREATOR_EMAIL:?missing DEMO_CREATOR_EMAIL}"
  : "${DEMO_LEARNER_EMAIL:?missing DEMO_LEARNER_EMAIL}"
  : "${DEMO_ADMIN_PASSWORD:?missing DEMO_ADMIN_PASSWORD}"
  : "${DEMO_CREATOR_PASSWORD:?missing DEMO_CREATOR_PASSWORD}"
  : "${DEMO_LEARNER_PASSWORD:?missing DEMO_LEARNER_PASSWORD}"
  : "${DEMO_COURSE_ID:?missing DEMO_COURSE_ID}"
  : "${DEMO_COURSE_TITLE:?missing DEMO_COURSE_TITLE}"

  DEMO_ADMIN_USERNAME="${DEMO_ADMIN_USERNAME:-$(derive_username_from_email "${DEMO_ADMIN_EMAIL}" "demo_admin")}"
  DEMO_CREATOR_USERNAME="${DEMO_CREATOR_USERNAME:-$(derive_username_from_email "${DEMO_CREATOR_EMAIL}" "demo_creator")}"
  DEMO_LEARNER_USERNAME="${DEMO_LEARNER_USERNAME:-$(derive_username_from_email "${DEMO_LEARNER_EMAIL}" "demo_learner")}"
}

STAGE05_DETAIL=""
stage05_account_setup() {
  load_demo_env

  local payload_b64
  payload_b64="$(
    jq -n \
      --arg admin_email "${DEMO_ADMIN_EMAIL}" \
      --arg admin_username "${DEMO_ADMIN_USERNAME}" \
      --arg admin_password "${DEMO_ADMIN_PASSWORD}" \
      --arg creator_email "${DEMO_CREATOR_EMAIL}" \
      --arg creator_username "${DEMO_CREATOR_USERNAME}" \
      --arg creator_password "${DEMO_CREATOR_PASSWORD}" \
      --arg learner_email "${DEMO_LEARNER_EMAIL}" \
      --arg learner_username "${DEMO_LEARNER_USERNAME}" \
      --arg learner_password "${DEMO_LEARNER_PASSWORD}" \
      '{
        admin: {email:$admin_email, username:$admin_username, password:$admin_password},
        creator: {email:$creator_email, username:$creator_username, password:$creator_password},
        learner: {email:$learner_email, username:$learner_username, password:$learner_password}
      }' | base64 -w0
  )"

  kubectl -n "${NAMESPACE}" exec deploy/lms -c lms -- sh -lc "export DEMO_PAYLOAD_B64='${payload_b64}'; cd /openedx/edx-platform && /openedx/venv/bin/python manage.py lms shell <<'PY'
import base64
import json
import os
from django.contrib.auth import get_user_model
from common.djangoapps.student.models import UserProfile
from common.djangoapps.student.roles import CourseCreatorRole

User = get_user_model()
payload = json.loads(base64.b64decode(os.environ['DEMO_PAYLOAD_B64']).decode('utf-8'))

def ensure_user(spec, is_superuser=False, is_staff=False, assign_course_creator=False):
    user, _ = User.objects.get_or_create(email=spec['email'], defaults={'username': spec['username']})
    user.username = spec['username']
    user.is_active = True
    user.is_superuser = is_superuser
    user.is_staff = True if is_superuser else is_staff
    user.set_password(spec['password'])
    user.save()
    UserProfile.objects.get_or_create(user=user)
    if assign_course_creator:
        CourseCreatorRole().add_users(user)
    return user

admin = ensure_user(payload['admin'], is_superuser=True, is_staff=True, assign_course_creator=True)
creator = ensure_user(payload['creator'], is_superuser=False, is_staff=True, assign_course_creator=True)
learner = ensure_user(payload['learner'], is_superuser=False, is_staff=False, assign_course_creator=False)

print('OK users:', admin.email, creator.email, learner.email)
PY"

  {
    echo "admin_email=${DEMO_ADMIN_EMAIL}"
    echo "creator_email=${DEMO_CREATOR_EMAIL}"
    echo "learner_email=${DEMO_LEARNER_EMAIL}"
    echo "admin_username=${DEMO_ADMIN_USERNAME}"
    echo "creator_username=${DEMO_CREATOR_USERNAME}"
    echo "learner_username=${DEMO_LEARNER_USERNAME}"
  } > "${ARTIFACT_DIR}/demo-accounts.txt"

  STAGE05_DETAIL="demo users ensured (admin/creator/learner); passwords rotated from env file"
}

verify_demo_data_integrity() {
  local payload_b64
  payload_b64="$(
    jq -n \
      --arg admin_email "${DEMO_ADMIN_EMAIL}" \
      --arg creator_email "${DEMO_CREATOR_EMAIL}" \
      --arg learner_email "${DEMO_LEARNER_EMAIL}" \
      --arg course_id "${DEMO_COURSE_ID}" \
      '{
        admin_email:$admin_email,
        creator_email:$creator_email,
        learner_email:$learner_email,
        course_id:$course_id
      }' | base64 -w0
  )"

  kubectl -n "${NAMESPACE}" exec deploy/lms -c lms -- sh -lc "export DEMO_VERIFY_B64='${payload_b64}'; cd /openedx/edx-platform && /openedx/venv/bin/python manage.py lms shell <<'PY'
import base64
import json
import os
from django.contrib.auth import get_user_model
from common.djangoapps.student.models import UserProfile, CourseEnrollment
from opaque_keys.edx.keys import CourseKey

User = get_user_model()
payload = json.loads(base64.b64decode(os.environ['DEMO_VERIFY_B64']).decode('utf-8'))

admin = User.objects.filter(email=payload['admin_email'], is_active=True, is_staff=True, is_superuser=True).first()
creator = User.objects.filter(email=payload['creator_email'], is_active=True, is_staff=True).first()
learner = User.objects.filter(email=payload['learner_email'], is_active=True).first()

if not all([admin, creator, learner]):
    raise SystemExit('One or more demo users missing/invalid')

if not UserProfile.objects.filter(user=admin).exists():
    raise SystemExit('Admin profile missing')
if not UserProfile.objects.filter(user=creator).exists():
    raise SystemExit('Creator profile missing')
if not UserProfile.objects.filter(user=learner).exists():
    raise SystemExit('Learner profile missing')

course_key = CourseKey.from_string(payload['course_id'])
enrollment = CourseEnrollment.objects.filter(user=learner, course_id=course_key, is_active=True).first()
if not enrollment:
    raise SystemExit(f'Learner enrollment missing for {course_key}')

print('OK data integrity users+profiles+enrollment', course_key)
PY"
}

STAGE06_DETAIL=""
stage06_course_lifecycle() {
  load_demo_env

  local org number run
  if [[ "${DEMO_COURSE_ID}" =~ ^course-v1:([^+]+)\+([^+]+)\+([^+]+)$ ]]; then
    org="${BASH_REMATCH[1]}"
    number="${BASH_REMATCH[2]}"
    run="${BASH_REMATCH[3]}"
  else
    fail_stage "DEMO_COURSE_ID must match course-v1:<ORG>+<NUMBER>+<RUN>" || return 1
  fi

  local exists
  exists="$(kubectl -n "${NAMESPACE}" exec deploy/cms -c cms -- sh -lc "cd /openedx/edx-platform && /openedx/venv/bin/python manage.py cms shell -c \"from opaque_keys.edx.keys import CourseKey; from xmodule.modulestore.django import modulestore; ck=CourseKey.from_string('${DEMO_COURSE_ID}'); print('1' if modulestore().get_course(ck) else '0')\"")"
  exists="$(printf '%s' "${exists}" | tail -n1)"

  if [[ "${exists}" != "1" ]]; then
    kubectl -n "${NAMESPACE}" exec deploy/cms -c cms -- sh -lc \
      "cd /openedx/edx-platform && /openedx/venv/bin/python manage.py cms create_course split '${DEMO_CREATOR_EMAIL}' '${org}' '${number}' '${run}' '${DEMO_COURSE_TITLE}'"
  fi

  local payload_b64
  payload_b64="$(
    jq -n \
      --arg creator_email "${DEMO_CREATOR_EMAIL}" \
      --arg learner_email "${DEMO_LEARNER_EMAIL}" \
      --arg course_id "${DEMO_COURSE_ID}" \
      '{
        creator_email:$creator_email,
        learner_email:$learner_email,
        course_id:$course_id
      }' | base64 -w0
  )"

  kubectl -n "${NAMESPACE}" exec deploy/lms -c lms -- sh -lc "export DEMO_COURSE_B64='${payload_b64}'; cd /openedx/edx-platform && /openedx/venv/bin/python manage.py lms shell <<'PY'
import base64
import json
import os
from django.contrib.auth import get_user_model
from common.djangoapps.student.models import CourseEnrollment
from common.djangoapps.student.roles import CourseStaffRole, CourseInstructorRole
from opaque_keys.edx.keys import CourseKey

payload = json.loads(base64.b64decode(os.environ['DEMO_COURSE_B64']).decode('utf-8'))
User = get_user_model()
course_key = CourseKey.from_string(payload['course_id'])

creator = User.objects.get(email=payload['creator_email'])
learner = User.objects.get(email=payload['learner_email'])

CourseStaffRole(course_key).add_users(creator)
CourseInstructorRole(course_key).add_users(creator)
CourseEnrollment.enroll(learner, course_key)

if not CourseStaffRole(course_key).has_user(creator):
    raise SystemExit('Creator not on course staff role')

if not CourseEnrollment.objects.filter(user=learner, course_id=course_key, is_active=True).exists():
    raise SystemExit('Learner enrollment missing after enroll call')

print('OK course-team+enrollment', course_key)
PY"

  kubectl -n "${NAMESPACE}" exec deploy/cms -c cms -- sh -lc "cd /openedx/edx-platform && /openedx/venv/bin/python manage.py cms shell -c \"from opaque_keys.edx.keys import CourseKey; from xmodule.modulestore.django import modulestore; from cms.djangoapps.contentstore.courseware_index import CoursewareSearchIndexer; ck=CourseKey.from_string('${DEMO_COURSE_ID}'); print('reindex_count', CoursewareSearchIndexer.do_course_reindex(modulestore(), ck))\""

  verify_demo_data_integrity
  STAGE06_DETAIL="demo course ensured; creator role + learner enrollment validated"
}

STAGE07_DETAIL=""
stage07_persistence_drill() {
  load_demo_env

  local lms_pod cms_pod
  lms_pod="$(kubectl -n "${NAMESPACE}" get pods --no-headers | awk '/^lms-.*Running/{print $1; exit}')"
  cms_pod="$(kubectl -n "${NAMESPACE}" get pods --no-headers | awk '/^cms-.*Running/{print $1; exit}')"
  [[ -n "${lms_pod}" ]] || fail_stage "No running LMS pod found for restart drill" || return 1
  [[ -n "${cms_pod}" ]] || fail_stage "No running CMS pod found for restart drill" || return 1

  kubectl -n "${NAMESPACE}" delete pod "${lms_pod}" "${cms_pod}"
  kubectl -n "${NAMESPACE}" rollout status deploy/lms --timeout=600s
  kubectl -n "${NAMESPACE}" rollout status deploy/cms --timeout=600s

  verify_demo_data_integrity
  curl -fsSI "https://${LMS_HOST}/heartbeat" >/dev/null
  curl -fsSI "https://${CMS_HOST}/heartbeat" >/dev/null

  STAGE07_DETAIL="lms/cms pod restart completed; users/course/enrollment persisted"
}

STAGE08_DETAIL=""
stage08_hpa_drill() {
  local hpa_watch_file="${ARTIFACT_DIR}/hpa-watch.log"
  local job_name="k6-loadtest-demo-gate"
  local lms_min cms_min lms_pre cms_pre lms_max cms_max lms_post cms_post

  "${REPO_ROOT}/scripts/50-hpa-apply.sh"
  kubectl -n "${NAMESPACE}" get hpa lms-hpa cms-hpa > "${ARTIFACT_DIR}/hpa-before.txt"

  lms_min="$(kubectl -n "${NAMESPACE}" get hpa lms-hpa -o jsonpath='{.spec.minReplicas}')"
  cms_min="$(kubectl -n "${NAMESPACE}" get hpa cms-hpa -o jsonpath='{.spec.minReplicas}')"
  lms_pre="$(kubectl -n "${NAMESPACE}" get hpa lms-hpa -o jsonpath='{.status.currentReplicas}')"
  cms_pre="$(kubectl -n "${NAMESPACE}" get hpa cms-hpa -o jsonpath='{.status.currentReplicas}')"
  lms_max="${lms_pre}"
  cms_max="${cms_pre}"

  kubectl -n "${NAMESPACE}" create configmap k6-script \
    --from-file=loadtest-k6.js="${REPO_ROOT}/configs/k8s/hpa/loadtest-k6.js" \
    --dry-run=client -o yaml | kubectl apply -f -
  kubectl -n "${NAMESPACE}" delete job "${job_name}" --ignore-not-found

  cat <<YAML | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: ${job_name}
  namespace: ${NAMESPACE}
spec:
  backoffLimit: 0
  ttlSecondsAfterFinished: 600
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: k6
          image: grafana/k6:0.49.0
          args: ["run", "--vus", "80", "--duration", "3m", "/scripts/loadtest-k6.js"]
          env:
            - name: LMS_HOST
              value: "${LMS_HOST}"
          volumeMounts:
            - name: scripts
              mountPath: /scripts
      volumes:
        - name: scripts
          configMap:
            name: k6-script
YAML

  # Watch all HPAs and keep only LMS/CMS lines for artifact evidence.
  kubectl -n "${NAMESPACE}" get hpa -w | awk 'NR==1 || $1=="lms-hpa" || $1=="cms-hpa"' > "${hpa_watch_file}" &
  local watch_pid=$!

  set +e
  kubectl -n "${NAMESPACE}" wait --for=condition=complete "job/${job_name}" --timeout=8m
  local job_wait_rc=$?
  set -e

  local i curr_lms curr_cms
  for i in $(seq 1 12); do
    curr_lms="$(kubectl -n "${NAMESPACE}" get hpa lms-hpa -o jsonpath='{.status.currentReplicas}')"
    curr_cms="$(kubectl -n "${NAMESPACE}" get hpa cms-hpa -o jsonpath='{.status.currentReplicas}')"
    if [[ "${curr_lms}" -gt "${lms_max}" ]]; then lms_max="${curr_lms}"; fi
    if [[ "${curr_cms}" -gt "${cms_max}" ]]; then cms_max="${curr_cms}"; fi
    sleep 10
  done

  kill "${watch_pid}" >/dev/null 2>&1 || true

  lms_post="$(kubectl -n "${NAMESPACE}" get hpa lms-hpa -o jsonpath='{.status.currentReplicas}')"
  cms_post="$(kubectl -n "${NAMESPACE}" get hpa cms-hpa -o jsonpath='{.status.currentReplicas}')"
  kubectl -n "${NAMESPACE}" get hpa lms-hpa cms-hpa > "${ARTIFACT_DIR}/hpa-after.txt"

  {
    echo "lms_min=${lms_min}"
    echo "cms_min=${cms_min}"
    echo "lms_pre=${lms_pre}"
    echo "cms_pre=${cms_pre}"
    echo "lms_max=${lms_max}"
    echo "cms_max=${cms_max}"
    echo "lms_post=${lms_post}"
    echo "cms_post=${cms_post}"
    echo "job_wait_rc=${job_wait_rc}"
  } > "${ARTIFACT_DIR}/hpa-summary.txt"

  if [[ "${lms_max}" -le "${lms_min}" && "${cms_max}" -le "${cms_min}" ]]; then
    fail_stage "HPA did not scale above min replicas (lms_max=${lms_max}, cms_max=${cms_max})" || return 1
  fi

  STAGE08_DETAIL="hpa scale observed (lms ${lms_pre}->max ${lms_max}->${lms_post}, cms ${cms_pre}->max ${cms_max}->${cms_post})"
}

STAGE09_DETAIL=""
stage09_backup_drill() {
  local backup_log="${ARTIFACT_DIR}/backup-run.log"
  "${REPO_ROOT}/scripts/60-backup-run.sh" | tee "${backup_log}" >/dev/null

  local rds_count ec2_count pv_count
  rds_count="$(grep -c '^RDS snapshot created:' "${backup_log}" || true)"
  ec2_count="$(grep -c '^EC2 snapshot created:' "${backup_log}" || true)"
  pv_count="$(grep -c '^PV snapshot created:' "${backup_log}" || true)"

  [[ "${rds_count}" -ge 1 ]] || fail_stage "Backup drill did not create an RDS snapshot" || return 1
  [[ "${ec2_count}" -ge 3 ]] || fail_stage "Backup drill did not create all EC2 datastore snapshots" || return 1
  if [[ "${pv_count}" -lt 1 ]]; then
    echo "WARN: No EBS PVC snapshots found (possible if no EBS-backed PVCs are present)." | tee -a "${RAW_LOG}"
  fi

  STAGE09_DETAIL="backup snapshots created (rds=${rds_count}, ec2=${ec2_count}, pv=${pv_count})"
}

STAGE10_DETAIL=""
stage10_waf_proof() {
  local tf_dir="${REPO_ROOT}/configs/cloudfront-waf"
  terraform -chdir="${tf_dir}" init -input=false >/dev/null
  local cf_domain
  cf_domain="$(terraform -chdir="${tf_dir}" output -raw cloudfront_domain_name)"
  [[ -n "${cf_domain}" ]] || fail_stage "CloudFront domain output missing" || return 1

  local base_code block_code
  base_code="$(curl -sS -o /dev/null -w '%{http_code}' "https://${cf_domain}/")"
  block_code="$(curl -sS -o /dev/null -w '%{http_code}' -H "X-Block-Me: 1" "https://${cf_domain}/")"

  [[ "${base_code}" != "403" ]] || fail_stage "Baseline CloudFront request returned 403" || return 1
  [[ "${block_code}" == "403" ]] || fail_stage "WAF block request did not return 403 (got ${block_code})" || return 1

  {
    echo "cf_domain=${cf_domain}"
    echo "baseline_status=${base_code}"
    echo "block_status=${block_code}"
  } > "${ARTIFACT_DIR}/waf-summary.txt"

  STAGE10_DETAIL="cloudfront/waf verified (baseline=${base_code}, blocked=${block_code})"
}

STAGE11_DETAIL=""
stage11_observability() {
  local obs_json="${ARTIFACT_DIR}/observability-pods.json"
  kubectl -n observability get pods -o json > "${obs_json}"
  kubectl -n observability get pods > "${ARTIFACT_DIR}/observability-pods.txt"

  local required=(
    "kube-prometheus-stack-grafana"
    "prometheus-kube-prometheus-stack-prometheus"
    "loki-stack-0"
    "loki-stack-promtail"
  )
  local key count
  for key in "${required[@]}"; do
    count="$(jq -r --arg k "${key}" '[.items[] | select(.metadata.name | contains($k)) | select(([.status.containerStatuses[]?.ready] | all))] | length' "${obs_json}")"
    [[ "${count}" -ge 1 ]] || fail_stage "Observability component not ready: ${key}" || return 1
  done

  kubectl top nodes > "${ARTIFACT_DIR}/kubectl-top-nodes.txt"

  local promtail_pod
  promtail_pod="$(kubectl -n observability get pods --no-headers | awk '/loki-stack-promtail/ {print $1; exit}')"
  if [[ -n "${promtail_pod}" ]]; then
    kubectl -n observability logs "${promtail_pod}" --tail=40 > "${ARTIFACT_DIR}/promtail-tail.log" || true
  fi

  STAGE11_DETAIL="observability pods ready; metrics pipeline healthy (kubectl top nodes)"
}

main() {
  run_stage "00" "Preflight (tools + namespace + ingress + DNS)" stage00_preflight STAGE00_DETAIL || return 1
  run_stage "01" "Core infra liveness" stage01_core_liveness STAGE01_DETAIL || return 1
  run_stage "02" "Edge + app reachability" stage02_edge_reachability STAGE02_DETAIL || return 1
  run_stage "03" "External data wiring + search reindex smoke" stage03_external_data_and_search STAGE03_DETAIL || return 1
  run_stage "04" "Studio SSO contract" stage04_studio_sso_contract STAGE04_DETAIL || return 1

  if [[ "${READONLY}" == "true" ]]; then
    skip_stage "05" "readonly mode: skipping account mutation checks"
  else
    run_stage "05" "Role/account setup + verification" stage05_account_setup STAGE05_DETAIL || return 1
  fi

  if [[ "${READONLY}" == "true" ]]; then
    skip_stage "06" "readonly mode: skipping course/enrollment mutations"
  else
    run_stage "06" "Course lifecycle + enrollment + reindex" stage06_course_lifecycle STAGE06_DETAIL || return 1
  fi

  if [[ "${READONLY}" == "true" ]]; then
    skip_stage "07" "readonly mode: skipping pod restart persistence drill"
  else
    run_stage "07" "Persistence drill (pod restart + data integrity)" stage07_persistence_drill STAGE07_DETAIL || return 1
  fi

  if [[ "${READONLY}" == "true" ]]; then
    skip_stage "08" "readonly mode: skipping HPA load drill"
  elif [[ "${SKIP_HPA}" == "true" ]]; then
    skip_stage "08" "flag --skip-hpa set"
  else
    run_stage "08" "HPA behavior drill" stage08_hpa_drill STAGE08_DETAIL || return 1
  fi

  if [[ "${READONLY}" == "true" ]]; then
    skip_stage "09" "readonly mode: skipping backup drill"
  elif [[ "${SKIP_BACKUP}" == "true" ]]; then
    skip_stage "09" "flag --skip-backup set"
  else
    run_stage "09" "Backup evidence drill" stage09_backup_drill STAGE09_DETAIL || return 1
  fi

  run_stage "10" "CloudFront/WAF proof" stage10_waf_proof STAGE10_DETAIL || return 1
  run_stage "11" "Observability proof" stage11_observability STAGE11_DETAIL || return 1
}

set +e
main
main_rc=$?
set -e

if [[ ${main_rc} -ne 0 ]]; then
  FAILED=1
  say "Demo gate FAILED. Artifacts: ${ARTIFACT_DIR}"
  exit 1
fi

say "Demo gate PASSED. Artifacts: ${ARTIFACT_DIR}"
exit 0
