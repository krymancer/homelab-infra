# Actual Budget — retained service

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

Stable release checked against upstream releases and **v26.10.0** source:
`ghcr.io/actualbudget/actual:26.10.0-alpine@sha256:67b1b5e9584e3e143b4f5c41e52b4506ed9cdd1072392d5ab5369f2d4fd0bffd`.
Alpine variant, non-root UID/GID 1001, port 5006; upstream `/health` probes.
Requests: 25m CPU / 128Mi; limits: 500m / 512Mi. PVC: `actual-data`, 2Gi.

This is independent of hledger: no existing journal, NAS mount, bank integration,
or migration is included. Existing budgets are retained; retention does not authorize imports or financial migration.

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

Open `https://actual.homelab.krymancer.dev`, authenticate, use an existing budget or deliberately create a separate budget,
reload, and verify persistence. HTTPS is needed for browser SharedArrayBuffer /
cross-origin-isolation support; preserve upstream COOP/COEP response headers.
No custom proxy headers are necessary for the stock server.

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

`kubectl kustomize k8s/apps/actual` and
`kubectl apply --dry-run=server -k k8s/apps/actual` passed on the live k3s context.
Only the expected missing namespace last-applied annotation warning occurred.
Registry manifests resolve the pinned release tags to these index digests and
include linux/amd64 (the cluster architecture). Non-root IDs were checked in
release-tag Dockerfiles. Runtime startup, memory under load, ingress source-IP
handling, certificate reflection and UI functionality remain post-sync checks.

## Upstream evidence

- https://github.com/actualbudget/actual/releases/tag/v26.10.0
- https://actualbudget.org/docs/install/docker/
- https://actualbudget.org/docs/config/
- https://github.com/actualbudget/actual/blob/v26.10.0/packages/sync-server/docker/alpine.Dockerfile
- https://github.com/actualbudget/actual/blob/v26.10.0/packages/sync-server/src/app-account.js
- https://github.com/actualbudget/actual/blob/v26.10.0/packages/sync-server/src/load-config.js

## Bank sync automation (Pluggy.ai)

This installation uses a server-side CronJob
`actual-bank-sync` that runs `@actual-app/api` `runBankSync()` daily at
**06:00 America/Fortaleza** against the in-cluster Actual Service.

The runner pins `@actual-app/api` to **26.10.0**, matching the deployed Actual
release. Update this pin alongside Actual upgrades: an older client can fail
with `out-of-sync-migrations` after a browser migrates the budget. The configured
Sync ID is required; a failed load never falls back to a different budget.
`getAccounts()` verifies that the budget really opened before fetching bank data.
Failures publishing the synced budget also fail the job.

Set `ACTUAL_SYNC_DRY_RUN=true` on a one-off Job to verify authentication and budget
compatibility without requesting bank transactions. This still downloads the
budget into the Job's temporary directory. Remove the flag for the actual sync.

### One-time Secret (required, not in Git)

```bash
# Budget Sync ID: Actual UI → Settings → Advanced → Sync ID
# (for "My Finances" this is the group id, not the file id)
#
# Session token: long-lived token from Actual's server sessions table, or
# replace with password-based seriouslag/actual-auto-sync later.

kubectl -n actual create secret generic actual-auto-sync \
  --from-literal=serverURL='http://actual.actual.svc.cluster.local:5006' \
  --from-literal=sessionToken='***' \
  --from-literal=budgetSyncId='***'
```

Manual one-shot:

```bash
kubectl -n actual create job --from=cronjob/actual-bank-sync actual-bank-sync-manual-$(date +%s)
kubectl -n actual logs -f job/actual-bank-sync-manual-...
```

This is independent of AUVP/auvp-financas Pluggy sync.

## Investment valuations (Pluggy)

The same 06:00 job also reads Pluggy's **investments** endpoint. Actual's built-in
Pluggy integration only imports accounts and account transactions; a brokerage
cash account is not the portfolio held by that brokerage.

`investment-sync.mjs` writes aggregate BRL valuations into explicitly configured
**off-budget** accounts. It excludes fully redeemed and pending positions,
requires complete pagination and unique investment IDs, and refuses stale,
unsupported-currency, or unsuccessful responses. Item refresh must be within
seven days; every active holding's valuation must be within 45 days. These are
latest available snapshots, not live prices. Notes retain the valuation-date
range and provider refresh time.

Every update is a dated adjustment to the account's existing balance, not a
second deposit of the whole portfolio. A deterministic transaction ID allows a
same-day correction without duplicate transactions. A no-change rerun makes no
write. Later real contributions/withdrawals already in the account are included
when computing the remaining adjustment. These adjustments combine valuation
changes and any unrecorded investment flows: **do not report them as pure return,
salary, dividends, or realized profit**. Budget categories are not changed.

### Private configuration

The `actual-investment-sync` Kubernetes Secret contains:

- `clientId` and `clientSecret`: the existing Pluggy application credentials.
- `sources`: a JSON array with one entry per aggregated portfolio. Each entry has
  `key` (stable lowercase identifier), `itemId` (Pluggy connection), `accountId`
  (Actual target), and `accountName` (setup name).

Do not commit credentials, connection IDs, budget exports, or real source JSON.
The Secret must be provisioned before enabling the updated CronJob. It is a
separate copy of the existing Actual Pluggy credentials; update it if those
credentials or connections change. `ACTUAL_INVESTMENTS_ENABLED=false` disables
only this extension, leaving normal bank synchronization enabled.

### Initial setup and validation

`investment-setup.mjs` defaults to `validate`. It downloads and exports the budget,
then launches a separate process with a fresh data directory and **no Actual
server URL or credentials**. That process imports the detached export and checks
account setup, exact valuations, preserved on-budget balances, and duplicate-free
repeat runs. It does not publish the detached copy.

The one-time `apply` mode performs the same setup against the configured budget
and calls `api.sync()`. Before applying, take a private backup of the complete
Actual data and verify the detached validation. Run setup in an isolated one-off
Job, not the recurring CronJob, using the same Secret references. Mount the
setup script and `investment-sync.mjs` together. Capture `SETUP_ACCOUNT_IDS` and
save those target IDs into the private `sources` configuration before enabling
recurring investment sync.

Optional setup-only source fields:

- `legacyAccountIds`: off-budget accounts to consolidate. Actual transfers their
  balances into the aggregate account and closes them, preserving history.
- `cashAccountId`, `cashAccountName`, `providerCashAccountId`: an existing linked
  brokerage cash account to relabel and reconcile once against Pluggy's cash
  balance. Its bank-sync link stays attached; the portfolio is held separately.

Recurring runs never close accounts or reset brokerage cash. Legacy source
fields may be removed from the Secret after setup. Existing spending-account
balance discrepancies are outside this investment migration.

Local regression checks:

```bash
node --test k8s/apps/actual/investment-sync.test.mjs
node --check k8s/apps/actual/run-bank-sync.mjs
```
