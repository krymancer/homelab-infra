# authentik standalone retained service

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

## Pinned deployment and isolation

- Current stable **2026.8.2**, published 2026-09-09; verified with GitHub latest stable on 2026-09-16.
- Server and worker: `ghcr.io/goauthentik/server:2026.8.2`, pinned by OCI index digest.
- Independent PostgreSQL: `postgres:16.15-bookworm`, pinned by OCI index digest (supported range: PostgreSQL 14–18).
- Plain Kubernetes manifests faithfully adapt the **released 2026.8.2** official Compose services:
  server + worker + PostgreSQL. **No Redis** is required by this release.
- **No existing login integration, providers, forward-auth middleware, privileged containers, host mounts,
  Docker socket, Kubernetes RBAC grants, or automatically managed outposts.**
  Outpost discovery is explicitly off, embedded outpost is disabled, and Kubernetes service-account tokens are not mounted.
- UID/GID 1000 for authentik, UID/GID 999 for PostgreSQL; capabilities dropped, no privilege escalation.
- Shared server/worker file storage: `authentik-data` 2Gi mounted at `/data` (current release path, not legacy `/media`).
  Database: `postgres-data` 10Gi. Both local-path RWO, intentionally single-node, not HA.
  Server and worker can share RWO on the same node; do not scale this architecture across nodes.
- Each authentik process gets a 512Mi memory-backed `/dev/shm`, as in the upstream Compose recommendation.
  Its actual use counts against each container memory limit. Web workers=2, background worker processes=1/threads=2.
- Memory requests: server 768Mi + worker 768Mi + DB 256Mi. Limits: server 1536Mi + worker 1536Mi + DB 768Mi.
  CPU requests: 200m/200m/100m; CPU limits: 2/2/1 cores. These are initial resource budgets, not guarantees under load.
  authentik and Reactive Resume together request **2.5Gi** RAM and permit **5.5Gi** maximum container RAM.
  Roll out sequentially and measure node capacity before adding the other apps.

## Prerequisites / GitOps

Use this directory as a plain ArgoCD Directory source. Requires Traefik (`ingressClassName: traefik`),
`local-path`, `authentik/homelab-wildcard-tls`, and LAN/Tailscale DNS `auth.homelab.krymancer.dev` pointing to ingress.
The parent infrastructure owns ArgoCD Application creation, DNS and certificate reflection.
No public tunnel route should be added for this service.
TLS terminates at Traefik and forwards HTTP 9000 to the server. PostgreSQL is ClusterIP-only;
`AUTHENTIK_POSTGRESQL__SSLMODE=disable` is explicit for this private, same-node non-TLS PostgreSQL.
No SMTP or external identity source is configured. Error reporting is off.

From the repository root:

```sh
python3 k8s/apps/authentik/provision-secrets.py
kubectl apply --dry-run=server -f k8s/apps/authentik/
```

The script checks context `homelab-alt`, creates only namespace + `trial-secrets`, and verifies both by read-back.
Repeat runs do not rotate credentials or overwrite mismatches. No secret-bearing apply annotation is created.
It generates a Django-compatible PBKDF2-SHA256 bootstrap verifier (1,000,000 rounds) and passes
`AUTHENTIK_BOOTSTRAP_PASSWORD_HASH` to **the worker only**, as documented for automated installation.
No admin API token is provisioned. The raw admin password never enters the Kubernetes Secret or Git.
Private recovery file, **0600** in a **0700** directory:

`/home/junho/.hermes/profiles/warden/homelab-app-trials/authentik.json`

Read locally using a private editor/password manager; never paste its contents into chat, logs, or Git.
It holds the generated `login_password`, username `akadmin`, and the Secret recovery data.

## User bootstrap after parent GitOps rollout

1. Wait for PostgreSQL, server migrations, and worker bootstrap. Probes allow up to 15 minutes of startup.
2. Open **https://auth.homelab.krymancer.dev** and sign in as **akadmin** with the private file's `login_password`.
   The documented automated bootstrap skips initial password setup. Do not create a second admin through a public setup flow.
3. Set your admin email and enroll MFA. Test logout/login before configuring anything else.
4. Keep it a standalone retained service: do not add production providers, sources, proxy integrations or outposts.
   SMTP/password recovery requires explicit future configuration; keep the private recovery file secure.
5. Bootstrap password hashes are read only on first initialization. Changing this Secret later does **not** reset an
   existing admin's password. Use authentik's documented recovery procedure if necessary.

Post-rollout checks (not performed during preparation):

```sh
kubectl -n authentik rollout status deployment/postgres --timeout=300s
kubectl -n authentik rollout status deployment/authentik-server --timeout=900s
kubectl -n authentik rollout status deployment/authentik-worker --timeout=900s
kubectl -n authentik get pods,pvc,ingress
curl --fail --show-error https://auth.homelab.krymancer.dev/-/health/ready/
```

Check the worker is ready as well as the server, then actually log in, enroll MFA and exercise logout/login.
Readiness is not a substitute for a tested bootstrap. Shared-memory, DB migration, and volume permission issues need live rollout checks.

## Persistence / rollback

PVCs have `Prune=false,Delete=false` for ArgoCD. Manual PVC deletion can still destroy local-path data.
Back up PostgreSQL, `/data`, and the private recovery file before upgrading. Recreate updates have brief downtime.
Rolling back only an image does not roll back database migrations. Restore a matching verified backup when required.
Never rotate PostgreSQL credentials only by changing the Secret; coordinate the database change and consumer restarts.

## Historical preparation checks

All exact image tags/digests were resolved from the registries, including amd64/arm64 manifests.
YAML parsed and all resources passed Kubernetes server-side dry-run. Provisioning and repeat provisioning passed;
Secret contents were compared in memory without printing them. Only namespaces and Secrets were changed live.
No workload was deployed during preparation. The retained installation is now deployed
through ArgoCD; preparation checks are not claims of current login/restore testing.

Official release-specific references:
- https://github.com/goauthentik/authentik/releases/tag/version/2026.8.2
- https://github.com/goauthentik/authentik/blob/version/2026.8.2/lifecycle/container/compose.yml
- https://github.com/goauthentik/authentik/blob/version/2026.8.2/website/docs/install-config/automated-install.mdx
- https://github.com/goauthentik/authentik/blob/version/2026.8.2/website/docs/install-config/configuration/configuration.mdx
- https://github.com/goauthentik/authentik/blob/version/2026.8.2/authentik/lib/default.yml
- https://github.com/goauthentik/authentik/blob/version/2026.8.2/lifecycle/container/Dockerfile
- https://docs.goauthentik.io/install-config/install/docker-compose/
