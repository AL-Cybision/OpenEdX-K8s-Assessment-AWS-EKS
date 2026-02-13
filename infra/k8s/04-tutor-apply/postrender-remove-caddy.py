#!/usr/bin/env python3
import os
import sys
import re

try:
    import yaml
except Exception as exc:  # pragma: no cover
    sys.stderr.write(f"PyYAML is required: {exc}\n")
    sys.exit(1)

DROP_KINDS = {"Deployment", "Service", "ConfigMap", "PersistentVolumeClaim", "Job", "Namespace"}
# Drop Tutor's Caddy edge proxy resources. Keep MFE's configmap (it is mounted
# by the MFE container image) so the MFE pod can start.
DROP_NAME_PREFIXES = ("caddy",)

LMS_HOST = os.environ.get("LMS_HOST", "lms.openedx.local")
CMS_HOST = os.environ.get("CMS_HOST", "studio.openedx.local")

PROBE_CONFIG = {
    "lms": {
        "type": "http",
        "port": 8000,
        "path": "/heartbeat",
        "delay": 60,
        "host_header": LMS_HOST,
    },
    "cms": {
        "type": "http",
        "port": 8000,
        "path": "/heartbeat",
        "delay": 60,
        "host_header": CMS_HOST,
    },
    "mfe": {"type": "http", "port": 8002, "path": "/", "delay": 20},
    "meilisearch": {"type": "http", "port": 7700, "path": "/health", "delay": 20},
    "smtp": {"type": "tcp", "port": 8025, "delay": 20},
    "lms-worker": {"type": "exec", "cmd": ["sh", "-c", "ps aux | grep -q '[c]elery'"], "delay": 30},
    "cms-worker": {"type": "exec", "cmd": ["sh", "-c", "ps aux | grep -q '[c]elery'"], "delay": 30},
}

MEDIA_PVC_NAME = "openedx-media"
MEDIA_VOLUME_NAME = "openedx-media"
MEDIA_MOUNT_PATH = "/openedx/media"
MFE_SERVICE_NAME = "mfe"
MFE_CADDY_CONFIGMAP_PREFIX = "mfe-caddy-config"
LEARNER_DASHBOARD_REDIRECT_URL = f"https://{LMS_HOST}/dashboard"


def build_probe(cfg: dict) -> dict:
    probe = {
        "initialDelaySeconds": cfg.get("delay", 20),
        "periodSeconds": 10,
        "timeoutSeconds": 5,
        "failureThreshold": 3,
    }
    if cfg["type"] == "http":
        http_get = {"path": cfg["path"], "port": cfg["port"], "scheme": "HTTP"}
        host_header = cfg.get("host_header")
        if host_header:
            http_get["httpHeaders"] = [{"name": "Host", "value": host_header}]
        probe["httpGet"] = http_get
    elif cfg["type"] == "tcp":
        probe["tcpSocket"] = {"port": cfg["port"]}
    elif cfg["type"] == "exec":
        probe["exec"] = {"command": cfg["cmd"]}
    return probe


def add_probes(doc: dict) -> None:
    if doc.get("kind") != "Deployment":
        return
    spec = doc.get("spec", {}).get("template", {}).get("spec", {})
    containers = spec.get("containers", [])
    for c in containers:
        name = c.get("name")
        cfg = PROBE_CONFIG.get(name)
        if not cfg:
            continue
        if "livenessProbe" not in c:
            c["livenessProbe"] = build_probe(cfg)
        if "readinessProbe" not in c:
            c["readinessProbe"] = build_probe(cfg)


def add_media_mounts(doc: dict) -> None:
    if doc.get("kind") != "Deployment":
        return
    name = (doc.get("metadata") or {}).get("name")
    if name not in {"lms", "cms"}:
        return

    spec = doc.get("spec", {}).get("template", {}).get("spec", {})
    volumes = spec.setdefault("volumes", [])
    if not any(v.get("name") == MEDIA_VOLUME_NAME for v in volumes):
        volumes.append(
            {
                "name": MEDIA_VOLUME_NAME,
                "persistentVolumeClaim": {"claimName": MEDIA_PVC_NAME},
            }
        )

    containers = spec.get("containers", [])
    for c in containers:
        if c.get("name") != name:
            continue
        mounts = c.setdefault("volumeMounts", [])
        if any(m.get("name") == MEDIA_VOLUME_NAME for m in mounts):
            continue
        mounts.append({"name": MEDIA_VOLUME_NAME, "mountPath": MEDIA_MOUNT_PATH})


def normalize_service_types(doc: dict) -> None:
    if doc.get("kind") != "Service":
        return
    name = (doc.get("metadata") or {}).get("name")
    if name != MFE_SERVICE_NAME:
        return

    spec = doc.setdefault("spec", {})
    spec["type"] = "ClusterIP"
    spec.pop("externalTrafficPolicy", None)
    for port in spec.get("ports", []):
        port.pop("nodePort", None)


def patch_mfe_caddyfile(doc: dict) -> None:
    if doc.get("kind") != "ConfigMap":
        return
    meta = doc.get("metadata") or {}
    name = meta.get("name", "")
    if not name.startswith(MFE_CADDY_CONFIGMAP_PREFIX):
        return

    data = doc.setdefault("data", {})
    caddyfile = data.get("Caddyfile")
    if not isinstance(caddyfile, str):
        return

    redirect_block = (
        "    @mfe_learner-dashboard {\n"
        "        path /learner-dashboard /learner-dashboard/*\n"
        "    }\n"
        f"    redir @mfe_learner-dashboard {LEARNER_DASHBOARD_REDIRECT_URL} 302\n"
    )

    # Replace learner-dashboard static handle with redirect to LMS dashboard.
    learner_dashboard_handle_pattern = re.compile(
        r"\n\s*@mfe_learner-dashboard\s*\{\s*path /learner-dashboard /learner-dashboard/\*\s*\}\s*"
        r"handle @mfe_learner-dashboard \{\s*uri strip_prefix /learner-dashboard\s*"
        r"root \* /openedx/dist/learner-dashboard\s*try_files /\{path\} /index\.html\s*"
        r"file_server\s*\}\s*\n",
        re.MULTILINE,
    )

    if learner_dashboard_handle_pattern.search(caddyfile):
        data["Caddyfile"] = learner_dashboard_handle_pattern.sub("\n" + redirect_block + "\n", caddyfile)
        return

    # If upstream template changes and no learner-dashboard block is found,
    # insert redirect once after the mfe_config proxy section.
    if "redir @mfe_learner-dashboard" not in caddyfile:
        anchor = "reverse_proxy /api/mfe_config/v1* lms:8000 {\n"
        idx = caddyfile.find(anchor)
        if idx != -1:
            end = caddyfile.find("}\n", idx)
            if end != -1:
                insert_at = end + 2
                data["Caddyfile"] = caddyfile[:insert_at] + "\n" + redirect_block + "\n" + caddyfile[insert_at:]


def should_drop(doc: dict) -> bool:
    if not isinstance(doc, dict):
        return False
    kind = doc.get("kind")
    meta = doc.get("metadata") or {}
    name = meta.get("name", "")

    if kind in {"Job", "Namespace"}:
        return True

    if kind in {"Deployment", "Service", "ConfigMap", "PersistentVolumeClaim"}:
        if name.startswith(DROP_NAME_PREFIXES):
            return True

    return False


in_docs = list(yaml.safe_load_all(sys.stdin))

out_docs = []
for d in in_docs:
    if not d or should_drop(d):
        continue
    add_probes(d)
    add_media_mounts(d)
    normalize_service_types(d)
    patch_mfe_caddyfile(d)
    out_docs.append(d)

yaml.safe_dump_all(out_docs, sys.stdout, sort_keys=False)
