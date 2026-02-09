#!/usr/bin/env python3
import os
import re
import sys

import yaml


REDACT_KEY_RE = re.compile(
    r"(?i)("
    r"pass(word)?|secret|token|private|"
    r"aws_.*(secret|access)|"
    r"api[_-]?key|client[_-]?secret|"
    r"encryption|signing"
    r")"
)


def sanitize(obj):
    if isinstance(obj, dict):
        out = {}
        for k, v in obj.items():
            ks = str(k)
            if REDACT_KEY_RE.search(ks):
                out[k] = "<REDACTED>"
            else:
                out[k] = sanitize(v)
        return out
    if isinstance(obj, list):
        return [sanitize(v) for v in obj]
    return obj


def main() -> int:
    repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
    default_in = os.path.expanduser("~/.local/share/tutor/config.yml")
    default_out = os.path.join(repo_root, "data-layer", "tutor", "config", "config.yml.sanitized")

    src = os.environ.get("TUTOR_CONFIG_IN", default_in)
    dst = os.environ.get("TUTOR_CONFIG_OUT", default_out)

    if not os.path.exists(src):
        sys.stderr.write(f"Input config not found: {src}\n")
        return 2

    os.makedirs(os.path.dirname(dst), exist_ok=True)

    with open(src, "r", encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}

    sanitized = sanitize(data)

    with open(dst, "w", encoding="utf-8") as f:
        yaml.safe_dump(sanitized, f, sort_keys=False)

    sys.stdout.write(f"Wrote sanitized Tutor config: {dst}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
