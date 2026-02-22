#!/usr/bin/env python3
"""
Derive an Amazon SES SMTP password from an AWS secret access key.

AWS SES SMTP auth uses:
- SMTP username: IAM access key ID
- SMTP password: derived from IAM secret access key (SigV4-style HMAC)

This script prints ONLY the derived SMTP password.
"""

import base64
import hmac
import hashlib
import os
import sys


def _sign(key: bytes, msg: str) -> bytes:
    return hmac.new(key, msg.encode("utf-8"), hashlib.sha256).digest()


def derive_ses_smtp_password(secret_access_key: str, region: str) -> str:
    # Algorithm documented by AWS for converting an IAM secret key to an SES SMTP password.
    # Do not log secrets; return only the derived password.
    k_date = _sign(("AWS4" + secret_access_key).encode("utf-8"), "11111111")
    k_region = _sign(k_date, region)
    k_service = _sign(k_region, "ses")
    k_signing = _sign(k_service, "aws4_request")
    signature = hmac.new(k_signing, "SendRawEmail".encode("utf-8"), hashlib.sha256).digest()
    return base64.b64encode(b"\x04" + signature).decode("utf-8")


def main() -> int:
    secret = os.environ.get("AWS_SECRET_ACCESS_KEY", "")
    region = os.environ.get("AWS_REGION", "") or os.environ.get("AWS_DEFAULT_REGION", "")
    if not secret or not region:
        sys.stderr.write("Missing AWS_SECRET_ACCESS_KEY or AWS_REGION/AWS_DEFAULT_REGION\n")
        return 2
    sys.stdout.write(derive_ses_smtp_password(secret, region))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

