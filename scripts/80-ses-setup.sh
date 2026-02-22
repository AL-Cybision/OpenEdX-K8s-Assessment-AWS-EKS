#!/usr/bin/env bash
set -euo pipefail

# SES email activation setup (staging/prod style).
# - Creates/ensures SES identities (domain and optional recipient email)
# - Creates an IAM user for SES SMTP and stores creds in Secrets Manager
# - Prints DNS records required for domain verification/DKIM (no secrets printed)
#
# IMPORTANT: SES sandbox vs production
# - If `ProductionAccessEnabled=false`, SES can only send to verified identities.
#   You can still verify your own email for activation testing.

# Default SES/domain/identity settings; override via env for your domain.
REGION="${REGION:-us-east-1}"
SES_DOMAIN="${SES_DOMAIN:-syncummah.com}"
FROM_EMAIL="${FROM_EMAIL:-no-reply@${SES_DOMAIN}}"
VERIFY_RECIPIENT_EMAIL="${VERIFY_RECIPIENT_EMAIL:-}"

IAM_USER_NAME="${IAM_USER_NAME:-openedx-ses-smtp}"
SECRETS_NAME="${SECRETS_NAME:-openedx-prod/ses-smtp}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Validate caller credentials early.
aws sts get-caller-identity --output json >/dev/null

# Print SES account mode so operator understands sandbox constraints.
ACCOUNT_JSON="$(aws sesv2 get-account --region "${REGION}" --output json)"
PROD_ACCESS="$(echo "${ACCOUNT_JSON}" | jq -r '.ProductionAccessEnabled')"
echo "SES ProductionAccessEnabled=${PROD_ACCESS} (region ${REGION})"

ensure_identity() {
  local identity="$1"
  if aws sesv2 get-email-identity --region "${REGION}" --email-identity "${identity}" >/dev/null 2>&1; then
    return 0
  fi
  aws sesv2 create-email-identity --region "${REGION}" --email-identity "${identity}" >/dev/null
}

ensure_identity "${SES_DOMAIN}"
ensure_identity "${FROM_EMAIL}"
if [[ -n "${VERIFY_RECIPIENT_EMAIL}" ]]; then
  ensure_identity "${VERIFY_RECIPIENT_EMAIL}"
fi

DOMAIN_JSON="$(aws sesv2 get-email-identity --region "${REGION}" --email-identity "${SES_DOMAIN}" --output json)"
DOMAIN_STATUS="$(echo "${DOMAIN_JSON}" | jq -r '.VerifiedForSendingStatus')"
DKIM_STATUS="$(echo "${DOMAIN_JSON}" | jq -r '.DkimAttributes.Status')"
echo "SES domain identity: ${SES_DOMAIN} VerifiedForSendingStatus=${DOMAIN_STATUS} DKIM=${DKIM_STATUS}"

if [[ "${DKIM_STATUS}" != "SUCCESS" ]]; then
  # Output DNS CNAMEs required for DKIM validation.
  echo
  echo "DNS: add these DKIM CNAME records for ${SES_DOMAIN}:"
  echo "${DOMAIN_JSON}" | jq -r '.DkimAttributes.Tokens[]' | while read -r tok; do
    printf "%s._domainkey.%s CNAME %s.dkim.amazonses.com\n" "${tok}" "${SES_DOMAIN}" "${tok}"
  done
fi

if [[ "${DOMAIN_STATUS}" != "true" ]]; then
  # Output DNS TXT required for domain identity verification.
  echo
  echo "DNS: add SES verification TXT record for ${SES_DOMAIN}:"
  aws ses get-identity-verification-attributes --region "${REGION}" --identities "${SES_DOMAIN}" --output json | \
    jq -r --arg d "${SES_DOMAIN}" '"_amazonses." + $d + " TXT " + .VerificationAttributes[$d].VerificationToken'
fi

if ! aws iam get-user --user-name "${IAM_USER_NAME}" >/dev/null 2>&1; then
  # Create dedicated SMTP IAM user if it does not exist yet.
  aws iam create-user --user-name "${IAM_USER_NAME}" >/dev/null
fi

# Minimal policy to send via SES SMTP.
POLICY_DOC="$(cat <<'JSON'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ses:SendEmail",
        "ses:SendRawEmail"
      ],
      "Resource": "*"
    }
  ]
}
JSON
)"
aws iam put-user-policy --user-name "${IAM_USER_NAME}" --policy-name "ses-send" --policy-document "${POLICY_DOC}" >/dev/null

# Create a new access key and store SMTP credentials in Secrets Manager.
# Do not print secrets.
KEY_JSON="$(aws iam create-access-key --user-name "${IAM_USER_NAME}" --output json)"
SMTP_USERNAME="$(echo "${KEY_JSON}" | jq -r '.AccessKey.AccessKeyId')"
export AWS_SECRET_ACCESS_KEY
AWS_SECRET_ACCESS_KEY="$(echo "${KEY_JSON}" | jq -r '.AccessKey.SecretAccessKey')"
export AWS_REGION="${REGION}"
SMTP_PASSWORD="$("${SCRIPT_DIR}/derive_ses_smtp_password.py")"
unset AWS_SECRET_ACCESS_KEY

SECRET_PAYLOAD="$(jq -n \
  --arg smtp_username "${SMTP_USERNAME}" \
  --arg smtp_password "${SMTP_PASSWORD}" \
  --arg smtp_host "email-smtp.${REGION}.amazonaws.com" \
  --arg smtp_port "587" \
  --arg smarthost "email-smtp.${REGION}.amazonaws.com::587" \
  --arg from_email "${FROM_EMAIL}" \
  '{smtp_username:$smtp_username,smtp_password:$smtp_password,smtp_host:$smtp_host,smtp_port:$smtp_port,smarthost:$smarthost,from_email:$from_email}')"

if aws secretsmanager describe-secret --region "${REGION}" --secret-id "${SECRETS_NAME}" >/dev/null 2>&1; then
  # Rotate secret value in place when secret already exists.
  aws secretsmanager put-secret-value --region "${REGION}" --secret-id "${SECRETS_NAME}" --secret-string "${SECRET_PAYLOAD}" >/dev/null
  SECRET_ARN="$(aws secretsmanager describe-secret --region "${REGION}" --secret-id "${SECRETS_NAME}" --query ARN --output text)"
else
  # Create secret first time and capture its ARN for apply step.
  SECRET_ARN="$(aws secretsmanager create-secret --region "${REGION}" --name "${SECRETS_NAME}" --secret-string "${SECRET_PAYLOAD}" --query ARN --output text)"
fi
echo
echo "Secrets Manager stored SMTP creds at: ${SECRET_ARN}"
echo "Next: apply to Kubernetes with: REGION=${REGION} SES_SMTP_SECRET_ID='${SECRET_ARN}' scripts/81-ses-apply.sh"

if [[ "${PROD_ACCESS}" != "true" ]]; then
  echo
  echo "NOTE: SES is in SANDBOX in ${REGION}. To send activation emails to arbitrary users, request SES production access."
  if [[ -n "${VERIFY_RECIPIENT_EMAIL}" ]]; then
    echo "For now you can verify the recipient identity (${VERIFY_RECIPIENT_EMAIL}) to receive activation emails."
  fi
fi
