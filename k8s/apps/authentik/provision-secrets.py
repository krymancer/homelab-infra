#!/usr/bin/env python3
"""Create only namespace + Secret; never print secrets or rotate existing ones.
Run from a trusted workstation with kubectl configured for the intended cluster.
Private recovery file is created before the Secret, exclusively and mode 0600.
"""
import base64
import hashlib
import json
import os
from pathlib import Path
import secrets
import stat
import subprocess
import sys

NAMESPACE = "authentik"
EXPECTED_CONTEXT = "homelab-alt"
PRIVATE_DIR = Path("/home/junho/.hermes/profiles/warden/homelab-app-trials")

def kubectl(*args, payload=None):
    result = subprocess.run(["kubectl", *args], input=json.dumps(payload) if payload is not None else None,
                            text=True, capture_output=True, check=False)
    if result.returncode:
        # kubectl errors can include request payloads. Never echo them for Secrets.
        raise RuntimeError("kubectl failed; inspect connectivity/RBAC separately (output suppressed)")
    return result.stdout

def lookup(kind, name, namespace=None):
    args = ["get", kind, name, "--ignore-not-found", "-o", "json"]
    if namespace:
        args.extend(["-n", namespace])
    raw = kubectl(*args)
    return json.loads(raw) if raw.strip() else None

def main():
    if kubectl("config", "current-context").strip() != EXPECTED_CONTEXT:
        raise RuntimeError("Refusing unexpected Kubernetes context")
    if PRIVATE_DIR.is_symlink():
        raise RuntimeError("Refusing symlinked private directory")
    PRIVATE_DIR.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(PRIVATE_DIR, 0o700)
    path = PRIVATE_DIR / (NAMESPACE + ".json")
    existing = lookup("secret", "trial-secrets", NAMESPACE) if lookup("namespace", NAMESPACE) else None
    if path.exists():
        if path.is_symlink() or stat.S_IMODE(path.stat().st_mode) != 0o600:
            raise RuntimeError("Private file must be a regular, non-symlinked file with mode 0600")
        record = json.loads(path.read_text())
    else:
        if existing:
            raise RuntimeError("Secret exists without recovery file; refusing to replace credentials")
        password = secrets.token_urlsafe(32)
        data = {"POSTGRES_PASSWORD": secrets.token_hex(32)}
        if NAMESPACE == "authentik":
            salt = secrets.token_hex(16)
            digest = hashlib.pbkdf2_hmac("sha256", password.encode(), salt.encode(), 1000000)
            data.update({"AUTHENTIK_SECRET_KEY": secrets.token_urlsafe(60),
                         "AUTHENTIK_BOOTSTRAP_PASSWORD_HASH": "pbkdf2_sha256$1000000$" + salt + "$" + base64.b64encode(digest).decode()})
            username = "akadmin"
        else:
            data.update({"AUTH_SECRET": secrets.token_hex(32),
                         "DATABASE_URL": "postgresql://reactive_resume:" + data["POSTGRES_PASSWORD"] + "@postgres:5432/reactive_resume"})
            username = "Choose username and email in the registration UI; no account has been created yet"
        record = {"namespace": NAMESPACE, "username": username, "login_password": password, "secret_data": data}
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        with os.fdopen(fd, "w") as handle:
            json.dump(record, handle, indent=2)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
    if record.get("namespace") != NAMESPACE:
        raise RuntimeError("Recovery namespace mismatch")
    data = record["secret_data"]
    encoded = {k: base64.b64encode(v.encode()).decode() for k, v in data.items()}
    if not lookup("namespace", NAMESPACE):
        kubectl("create", "-f", "-", payload={"apiVersion":"v1", "kind":"Namespace", "metadata":{"name":NAMESPACE}})
    if not lookup("namespace", NAMESPACE):
        raise RuntimeError("Namespace read-back verification failed")
    if existing is None:
        kubectl("create", "-f", "-", payload={"apiVersion":"v1", "kind":"Secret", "metadata":{"name":"trial-secrets", "namespace":NAMESPACE}, "type":"Opaque", "data":encoded})
    actual = lookup("secret", "trial-secrets", NAMESPACE)
    if actual is None or actual.get("data") != encoded or actual.get("type") != "Opaque":
        raise RuntimeError("Secret differs from recovery file; refusing automatic rotation")
    print(f"Verified {NAMESPACE}/trial-secrets; private recovery file: {path} (0600)")

if __name__ == "__main__":
    try:
        main()
    except Exception:
        print("Provisioning failed safely; inspect context, RBAC, or private recovery file without publishing its contents.", file=sys.stderr)
        sys.exit(1)
