#!/usr/bin/env python3
"""Create prerequisites only; never deploy workloads or print secret values.

Run with an interpreter containing bcrypt. Existing secrets are never rotated.
The plaintext Homelable login is kept only in its Kubernetes Secret, not on disk
or in the pod environment. Back up both app Secrets separately from Git.
"""
import json
import secrets
import subprocess

import bcrypt


def kubectl(*args, payload=None):
    result = subprocess.run(
        ["kubectl", *args],
        input=json.dumps(payload) if payload is not None else None,
        text=True,
        capture_output=True,
    )
    if result.returncode:
        # API errors can echo request bodies: never print captured output.
        raise RuntimeError("kubectl prerequisite operation failed; inspect the target separately")
    return result.stdout


def ensure_secret(namespace, name, generate):
    kubectl("get", "namespace", namespace)
    existing = kubectl("get", "secret", name, "-n", namespace, "--ignore-not-found", "-o", "name")
    if not existing.strip():
        kubectl("create", "-f", "-", payload={
            "apiVersion": "v1", "kind": "Secret",
            "metadata": {"name": name, "namespace": namespace},
            "type": "Opaque", "stringData": generate(),
        })
    # Read back exact object, rendering names of keys only.
    keys = kubectl("get", "secret", name, "-n", namespace, "-o",
                   'go-template={{range $key, $value := .data}}{{$key}}{{"\\n"}}{{end}}')
    print(f"{namespace}/{name} keys: {', '.join(sorted(keys.splitlines()))}")


def homelable_credentials():
    password = secrets.token_urlsafe(32)
    return {
        "AUTH_USERNAME": "admin",
        "AUTH_PASSWORD_HASH": bcrypt.hashpw(password.encode(), bcrypt.gensalt(rounds=12)).decode(),
        "SECRET_KEY": secrets.token_hex(32),
        "BOOTSTRAP_PASSWORD": password,
    }


def main():
    for namespace in ("homelable", "termix"):
        exists = kubectl("get", "namespace", namespace, "--ignore-not-found", "-o", "name")
        if not exists.strip():
            kubectl("create", "-f", "-", payload={
                "apiVersion": "v1", "kind": "Namespace", "metadata": {"name": namespace},
            })
        kubectl("get", "namespace", namespace, "-o", "name")
    ensure_secret("homelable", "homelable-auth", homelable_credentials)
    ensure_secret("termix", "termix-crypto", lambda: {
        key: secrets.token_hex(32)
        for key in ("JWT_SECRET", "DATABASE_KEY", "ENCRYPTION_KEY", "INTERNAL_AUTH_TOKEN")
    })


if __name__ == "__main__":
    main()
