# Reactive Resume trial

## Pinned, minimal deployment

- Release **v5.3.0**, published 2026-09-06; verified against GitHub's latest stable release on 2026-09-16.
- App: `ghcr.io/amruthpillai/reactive-resume:v5.3.0`, pinned by OCI index digest in `deployment.yaml`.
- Database: independent `postgres:16.15-bookworm`, pinned by OCI index digest in `postgres.yaml`.
- Two containers only: app + PostgreSQL. **No Browserless/Chromium, Redis, S3/MinIO/SeaweedFS**.
  The *released v5.3.0 documentation*, not main, explicitly says browser-side PDF generation replaced Browserless in v5.1.0.
  Redis/S3 are optional for core resume creation; the AI Agent workspace is intentionally unavailable in this minimal trial.
- Local uploads: `resume-data` 5Gi at `/app/data`; database: `postgres-data` 10Gi.
- All PVCs use `local-path` with `Prune=false,Delete=false` for ArgoCD. Local-path is node-local and NOT a backup;
  manually deleting the PVC can delete its data. Database and uploads both need backup before upgrades.
- Memory requests: app 512Mi + DB 256Mi; limits: app 1Gi + DB 768Mi. CPU limits: 1 core each.
  PostgreSQL is bounded to 60 connections, 128MB shared buffers, 4MB work memory.
  Single replicas, Recreate deployment updates, non-root UID 1000/999, no service-account token mounts.

## Prerequisites / GitOps

Use this directory as a plain ArgoCD Directory source (no Helm/Kustomize rendering needed).
Requires the existing k3s `local-path` provisioner, Traefik IngressClass `traefik`, namespace TLS Secret
`homelab-wildcard-tls`, and LAN/Tailscale DNS `resume.homelab.krymancer.dev` pointing to the LAN ingress.
The parent infrastructure owns DNS, certificate reflection, and the ArgoCD Application.
Do not expose this trial through public tunnel routes or integrate any existing logins.

Secrets are deliberately **not** GitOps resources. From the repository root:

```sh
python3 k8s/apps/reactive-resume/provision-secrets.py
kubectl apply --dry-run=server -f k8s/apps/reactive-resume/
```

The provisioning script checks context `homelab-alt`, creates only the namespace and `trial-secrets`,
verifies their read-back, and is idempotent (never overwrites a mismatching Secret).
It sends secrets on stdin, never command-line arguments/stdout, and does not use secret-bearing apply annotations.
No workload is deployed by that script. After moving clusters, review the context guard explicitly.
Private recovery file, mode **0600**, parent directory **0700**:

`/home/junho/.hermes/profiles/warden/homelab-app-trials/reactive-resume.json`

It includes the database/auth keys and a generated `login_password` for the UI signup.
Read it only in a private local editor/password manager; do not paste it into chats, logs or Git.

## Saved AI-provider credential encryption

The app also requires the out-of-band Secret `reactive-resume-ai-encryption`, key
`ENCRYPTION_SECRET`, before its Deployment can start. v5.3.0 requires at least
32 characters; use a dedicated cryptographically random 32-byte hex value (64 characters).
Do not reuse or rotate `AUTH_SECRET` or database credentials to satisfy this requirement.
The deployment references the Secret through `secretKeyRef`; no key belongs in Git.

Before creating this Secret, inspect existing encryption references and key presence.
Reuse existing encryption material if present; **never overwrite or casually rotate it**:
saved provider credentials depend on this key and can become unreadable if it changes.
Generate only when absent, write a private durable backup **before rollout**, then create
using stdin (not CLI arguments or secret-bearing apply annotations). Verify exact key
read-back in memory without printing it. Keep the backup with database recovery material;
copy it to an approved independent encrypted backup destination for disaster recovery.
The local recovery copy alone does not protect against loss of this host.

Private recovery file (0600 in a 0700 directory; never commit or paste its contents):
`/home/junho/.hermes/profiles/warden/homelab-app-trials/encryption-backup/reactive-resume-ai-encryption.json`

The original `provision-secrets.py` does not create this additional Secret. On recovery,
restore its backed-up value before syncing the Deployment; do not generate a replacement
for a database containing encrypted provider credentials. Deploy workload changes only
through a PR merged into ArgoCD's tracked `main`, then verify exact revision and readiness.

This restores the provider-settings management prerequisite. Verify normal login and
`GET /api/auth/get-session`, then authenticated `GET /api/rpc/aiProviders/list` returns 200;
health checks alone do not establish that provider settings work. Saving/testing provider
keys, inference, and uploads are separate operations and are not performed by this fix.
The full AI Agent workspace remains unavailable: **Redis and S3-compatible private storage
are not configured**. No Redis/S3 services are added for provider management.

## User bootstrap after parent GitOps rollout

1. Wait for PostgreSQL and app readiness; the app automatically applies DB migrations at startup.
2. Open **https://resume.homelab.krymancer.dev** and register your own username/email with the private file's
   generated `login_password`. **An account is not created by provisioning**; that password is a prepared signup credential.
3. SMTP is intentionally absent. In this release email verification is not required for sign-in;
   verification/reset messages are logged by the app. Treat application logs as sensitive.
4. After the intended users register, set `FLAG_DISABLE_SIGNUPS` to `"true"` in `deployment.yaml` and let GitOps reconcile.
   Do not disable email/password auth, which is the only configured login method.
5. Create a resume, upload a photo, export a PDF in the browser, sign out/in, and verify data survives a controlled restart.
   Browser PDF export is the real functional test, not just HTTP health.

Post-rollout checks (not performed during preparation):

```sh
kubectl -n reactive-resume rollout status deployment/postgres --timeout=300s
kubectl -n reactive-resume rollout status deployment/reactive-resume --timeout=600s
kubectl -n reactive-resume get pods,pvc,ingress
curl --fail --show-error https://resume.homelab.krymancer.dev/api/health
```

If credentials are changed later, changing the Secret alone does not change PostgreSQL's persisted password.
Coordinate SQL credential changes and consumer restarts; the provisioning script deliberately refuses rotation.
Rollback app images only when DB migrations are backwards-compatible; otherwise restore a verified DB/uploads backup.

## Evidence and preparation checks

Registry OCI manifests were fetched successfully for all exact tags/digests (amd64 and arm64 available).
YAML parsed and all resources passed live Kubernetes server-side dry-run. Secret provisioning and its repeat run passed,
with byte-for-byte in-memory Secret read-back checks. Only namespaces and Secrets were mutated live;
PVC binding, pod startup, ingress TLS and UI/PDF workflows remain rollout acceptance checks.

Official version-specific sources:
- https://github.com/reactive-resume/reactive-resume/releases/tag/v5.3.0
- https://github.com/reactive-resume/reactive-resume/blob/v5.3.0/docs/self-hosting/docker.mdx
- https://github.com/reactive-resume/reactive-resume/blob/v5.3.0/.env.example
- https://github.com/reactive-resume/reactive-resume/blob/v5.3.0/Dockerfile
- https://github.com/reactive-resume/reactive-resume/blob/v5.3.0/packages/auth/src/config.ts
- https://github.com/docker-library/official-images/blob/master/library/postgres (16.15-bookworm tag verified 2026-09-16)
