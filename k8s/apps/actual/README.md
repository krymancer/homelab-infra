# Actual Budget — isolated trial

Stable release checked against upstream releases and **v26.9.0** source:
`ghcr.io/actualbudget/actual:26.9.0-alpine@sha256:1c14eef351234f4b5dd0433865b5de89d70bdbdc57368d5b07e910662c6498f9`.
Alpine variant, non-root UID/GID 1001, port 5006; upstream `/health` probes.
Requests: 25m CPU / 128Mi; limits: 500m / 512Mi. PVC: `actual-data`, 2Gi.

This is independent of hledger: no existing journal, NAS mount, bank integration,
or migration is included. Create a new disposable budget, not an import.

## First bootstrap (required before allowing other users)

Actual's stable password mode uses a shared server password, not open account
registration. Only `password` auth is enabled (header/OpenID login disabled).
There is no supported initial-password environment variable used here and no
app Secret is required; the password hash and sessions persist in `/data`.

For a race-free bootstrap, the integrating operator should initially omit
`ingress.yaml` from this app's kustomization, sync the remaining resources, and
use `kubectl -n actual port-forward svc/actual 5006:5006` from their own workstation.
Open `http://localhost:5006` (localhost is a browser secure context), set a strong
unique server password, then verify `/account/needs-bootstrap` returns
`data.bootstrapped: true`. Restore `ingress.yaml` to the kustomization and sync it
only after bootstrap and TLS reflection. This staged change is intentionally
left to the parent who controls integration/deployment; the delivered full
kustomization includes the final ingress. **Do not initially sync the entire
kustomization on a LAN with untrusted clients**: first visitor can claim an
uninitialized server. No signups remain once the password bootstrap is complete.

Open `https://actual.homelab.krymancer.dev`, authenticate, create a new trial budget,
reload, and verify persistence. HTTPS is needed for browser SharedArrayBuffer /
cross-origin-isolation support; preserve upstream COOP/COEP response headers.
No custom proxy headers are necessary for the stock server.

## GitOps integration prerequisites

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
  Service, Middleware and Ingress were **not** applied.

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

## Validation performed

`kubectl kustomize k8s/apps/actual` and
`kubectl apply --dry-run=server -k k8s/apps/actual` passed on the live k3s context.
Only the expected missing namespace last-applied annotation warning occurred.
Registry manifests resolve the pinned release tags to these index digests and
include linux/amd64 (the cluster architecture). Non-root IDs were checked in
release-tag Dockerfiles. Runtime startup, memory under load, ingress source-IP
handling, certificate reflection and UI functionality remain post-sync checks.

## Upstream evidence

- https://github.com/actualbudget/actual/releases/tag/v26.9.0
- https://actualbudget.org/docs/install/docker/
- https://actualbudget.org/docs/config/
- https://github.com/actualbudget/actual/blob/v26.9.0/packages/sync-server/docker/alpine.Dockerfile
- https://github.com/actualbudget/actual/blob/v26.9.0/packages/sync-server/src/app-account.js
- https://github.com/actualbudget/actual/blob/v26.9.0/packages/sync-server/src/load-config.js
