# DashLit — standalone retained service

## Retained service status

Permanent homelab service, managed by the existing ArgoCD app-of-apps from
`main` in this repository. Retention changes documentation and launcher categories
only: existing accounts, data, PVCs, encryption keys, Secret names (including any
`trial-secrets`), pinned images and LAN/Tailscale-only access remain unchanged.
Bootstrap instructions below are for initial installation/recovery, **not** steps
to rerun on the retained installation. Existing integrations remain as configured;
no SSO conversion, banking import, paid inference or AI Agent enablement is implied.

Persistence is not a backup. This promotion adds no backup schedule, independent
backup destination, restore test, HA or production-readiness guarantee. Retain
application data and its matching credentials/encryption material together.

Stable release **v1.1.1**, not the moving main/dev tag:
`ghcr.io/codewec/dashlit:v1.1.1@sha256:41b33c90d8ee8cd7ba469b181fb5ffb8cc2e4a2c35755ef1abb8fd6fe386500c`.
Non-root UID/GID 10001, port 8080; upstream `/api/auth/config` probes.
Requests: 25m CPU / 32Mi; limits: 500m / 192Mi; Go soft limit: 128MiB.
PVC: `dashlit-data`, 1Gi. Standalone, **not a replacement for Homepage**.

## Secret and safe first administrator

`dashlit/dashlit-secrets` was created directly through the Kubernetes API using
cryptographically random values, never written into this repository. Required
exact nonempty keys were verified without displaying values:

- `JWT_SECRET` (keep stable; changing it invalidates sessions)
- `INITIAL_ADMIN_PASSWORD` (one-time bootstrap password)

Username is `admin`. v1.1.1 supports `INITIAL_ADMIN_USERNAME` and
`INITIAL_ADMIN_PASSWORD`: it creates the administrator before serving requests
only if the database has no users. Both password and OIDC registration are
**disabled from the first start**. Password login remains enabled and OIDC is
not configured. Upstream release-tag implementation and README were checked;
this does not rely on an unreleased bootstrap feature.

After deployment, an authorized operator should transfer the initial password
from the Secret directly to a local password manager/clipboard, without printing
it into a chat, command log, terminal transcript or Git. For a local Wayland
workstation with `wl-copy` installed (not an agent tool-output channel):

```sh
kubectl -n dashlit get secret dashlit-secrets \
  -o jsonpath='{.data.INITIAL_ADMIN_PASSWORD}' | base64 --decode | wl-copy
```

Open `https://dashlit.homelab.krymancer.dev`, log in as `admin`, change the password
in the profile, clear the clipboard and save the new password securely. Select
private/authenticated dashboard visibility. Verify `/api/auth/config` reports
`passwordRegistrationEnabled: false`, `passwordLoginEnabled: true`, and
`oidcEnabled: false`. Verify an unauthenticated registration POST is rejected,
and dashboard changes survive a pod replacement.

Bootstrap env references may remain: upstream ignores them after any user
exists; they do not reset passwords. After verified login, optionally remove
both `INITIAL_ADMIN_*` env entries in Git and remove the bootstrap key from the
Secret (keep JWT_SECRET). If rebuilding with an empty PVC, reprovision a fresh
bootstrap password and restore both env entries before startup.

Update checks are disabled (`UPDATE_CHECK_ENABLED=false`). No monitoring targets,
OIDC, SSH, or external integrations are configured. Upstream icon searches can
contact Iconify/selfh.st when used; avoid them for a network-isolated deployment.
This configuration does not impose an egress NetworkPolicy.

## Initial-installation GitOps prerequisites (historical preparation)

- Parent owns the Argo Application and private Pi-hole records pointing at
  `192.168.0.20`; do not add a Cloudflare Tunnel or public router forwarding.
- Add this namespace to **both** reflector allowlists in
  `k8s/apps/cert-manager/wildcard-cert.yaml` and the live source Secret's
  corresponding annotations. This task deliberately does not edit shared files.
  Wait for `homelab-wildcard-tls` (keys `tls.crt`, `tls.key`) in this namespace
  before enabling the route. Never print Secret data or all annotations: old
  kubectl last-applied annotations may contain private keys.
- Ingress is Traefik `websecure` only, using reflected `homelab-wildcard-tls`.
  The local `lan-only` Middleware permits `192.168.0.0/24` and
  `100.64.0.0/10`, with no trust in arbitrary forwarded headers. Test from LAN
  and Tailscale after rollout. If Traefik sees a different source due to NAT,
  investigate the real source instead of blindly allowing pod CIDRs or trusting
  X-Forwarded-For. A private DNS record alone is not access control; do not
  publicly expose this ingress controller through a source-NAT proxy.
- Namespace and any documented app Secret were pre-created; workloads, PVC,
  Service, Middleware and Ingress were not applied during that preparation step.
  The retained installation is now deployed through its tracked Argo Application.

## Persistence, sizing and rollback

Single replica with `Recreate` prevents overlapping SQLite writers. `/data` is
backed by local-path RWO storage (single-node, not replicated, not a backup).
The PVC has `Prune=false` to guard routine GitOps pruning, but deleting the
namespace/PVC still destroys data with this storage class's Delete policy.
Back up a stopped app's complete `/data` before upgrades; for DashLit a SQLite
online backup is also possible. Roll back the image and restore the matching
backup if a migration is not backward-compatible. Do not delete the namespace
as an ordinary rollback. No SSH credentials or external integration credentials
are configured.

## Historical preparation validation

`kubectl kustomize k8s/apps/dashlit` and
`kubectl apply --dry-run=server -k k8s/apps/dashlit` passed on the live k3s context.
Only the expected missing namespace last-applied annotation warning occurred.
Registry manifests resolve the pinned release tags to these index digests and
include linux/amd64 (the cluster architecture). Non-root IDs were checked in
release-tag Dockerfiles. Runtime startup, memory under load, ingress source-IP
handling, certificate reflection and UI functionality remain post-sync checks.

## Upstream evidence

- https://github.com/codewec/dashlit/releases/tag/v1.1.1
- https://github.com/codewec/dashlit/blob/v1.1.1/README.md
- https://github.com/codewec/dashlit/blob/v1.1.1/Dockerfile
- https://github.com/codewec/dashlit/blob/v1.1.1/backend/internal/auth/auth.go
- https://github.com/codewec/dashlit/blob/v1.1.1/backend/internal/handlers/auth.go
