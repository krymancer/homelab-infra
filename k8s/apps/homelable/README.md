# Homelable 3.5.0

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

Full backend + web UI, SQLite/uploads on a 1Gi local-path PVC. Both containers share
one pod; a small nginx ConfigMap proxies API/WebSocket traffic over loopback rather
than relying on the Docker-only `backend` DNS name. Port 8080 permits non-root nginx.
Backend requests 96Mi / limit 256Mi; UI requests 16Mi / limit 64Mi.

## Authentication / disabled features

`homelable-auth` contains random `SECRET_KEY`, bcrypt `AUTH_PASSWORD_HASH`,
`AUTH_USERNAME=admin`, and a random 43-character `BOOTSTRAP_PASSWORD`. The plaintext
password is **not** injected into the workload. No private credential files are
created. Retrieve it only in a private terminal or password-manager workflow:

```sh
kubectl -n homelable get secret homelable-auth -o jsonpath='{.data.BOOTSTRAP_PASSWORD}' | base64 -d
```

The command deliberately reveals the login: do not paste its output into chat/logs.
Do not rotate SECRET_KEY casually; treat it as persistent application key material.
MCP is enabled as an authenticated loopback-connected sidecar (see below). Live view and
Homepage unauthenticated API keys are disabled. Scanner ranges are empty, HTTP
probes/service checks and scheduled Proxmox/MQTT sync are off. Default-deny **egress**
allows only the existing Traefik HTTPS endpoint for manual Proxmox inventory import.
Direct LAN/Internet scanning remains blocked even if UI settings are changed.
Loopback API calls and responses to inbound requests still work. k3s must enforce
NetworkPolicy (standard k3s network-policy controller); verify this after deployment.
The upstream status scheduler itself remains running; there is no global supported
scanner-disable env flag. No telemetry setting or analytics implementation found in
the pinned Homelable source. Egress deny also prevents external server callbacks;
browser-side fetching external diagram/icon URLs is not controlled by this policy.

## Prerequisites / deployment

- Namespace and application Secret are created out of band, never committed with values.
- Run `python3 k8s/apps/homelable/bootstrap-secrets.py` using a venv containing
  `bcrypt`. This idempotently creates **both** app namespaces/Secrets; it never
  rotates existing keys, prints credentials, or starts workloads.
- Add `homelable` and `termix` to BOTH source Secret reflection namespace lists
  on `default/homelab-wildcard-tls` (and its GitOps/certificate source).
  This shared configuration is intentionally not changed by these app manifests.
  Reflector then creates the TLS Secret in each namespace. Check key names only.
- Parent owns Argo Applications and private Pi-hole DNS records to `192.168.0.20`.
  Do not add public DNS/tunnel routes. LAN/Tailscale reachability is an infrastructure
  prerequisite, not a security boundary provided by an Ingress hostname.
- Validate: `kubectl apply --dry-run=server -f k8s/apps/APP/` (replace APP).
  Parent deploys the directory through Argo; bootstrap does not deploy it.
- Backup the PVC AND application Secret. `local-path` is node-local, not replicated;
  PVC deletion can delete the data. Single replica and Recreate avoid SQLite/RWO races.
- After rollout, verify startup, login, TLS, persistence across restart and memory
  usage. Resource limits are conservative initial resource limits, not upstream guarantees.

No host networking, privilege escalation, Linux capabilities, host mounts, Docker
socket, Kubernetes token, or remote SSH keys are supplied. Only the dedicated
read-only Proxmox inventory token described below is supplied to the backend.
All containers run as UID/GID 1000 with RuntimeDefault seccomp.

## Read-only Proxmox inventory

- Endpoint: `https://pve.homelab.krymancer.dev:443`, with `PROXMOX_VERIFY_TLS=true`.
  This uses the existing valid ingress certificate and route to Proxmox `alt`.
  The existing ingress-to-Proxmox transport is managed elsewhere; this change
  does not change its TLS settings (currently an upstream skip-verify transport).
- `homelable@pve!inventory` is privilege-separated, with **only PVEAuditor** at
  `/` (propagated) on BOTH the dedicated user and token. No root/monitoring token.
- Out-of-band Secret `homelable/homelable-proxmox` has `PROXMOX_TOKEN_ID` and
  `PROXMOX_TOKEN_SECRET`; inject via Secret references, never Git or browser.
  Create/update by stdin from an in-memory credential capture; do not log values
  or use secret-bearing CLI arguments / last-applied annotations.
- In the import form, use host above, port **443**, Verify TLS **on**, leave token
  fields empty (server fallback), and choose **Inventory only**, never canvas.
  API equivalent: `POST /api/v1/proxmox/test-connection`, then
  `POST /api/v1/proxmox/import-pending` with host/port/verify_tls only; poll the
  returned run using `/api/v1/scan/runs/{id}`. Read inventory before importing.
- Scheduled sync remains disabled. Scans, probes and service checks remain off.
- Pod-local `hostAliases` maps only the TLS hostname to the existing Traefik
  ClusterIP `10.43.213.255`; no DNS exceptions or global DNS edits are required.
  If that Service is recreated with a new IP, update the alias through GitOps.
  Egress allows only kube-system Traefik pods, TCP 8443 (Service post-DNAT).
  L3/L4 NetworkPolicy cannot restrict virtual hosts/paths on the shared ingress;
  other routes at that same HTTPS listener are reachable, not arbitrary networks.
- After a Secret update, restart the Homelable deployment and verify config,
  test-connection, inventory IDs, and unchanged canvas. Back up this Secret with
  the existing app credentials. Rollback by reverting the manifests and revoking
  only `homelable@pve!inventory`; do not delete inventory/PVC or other PVE users.

## MCP endpoint (3.5.0)

- URL: `https://homelable.homelab.krymancer.dev/mcp/` (Streamable HTTP).
- Uses the same TLS Ingress and LAN/Tailscale source allowlist as the UI. No
  public DNS/tunnel, NodePort, or separate externally exposed backend/MCP port.
- nginx forwards `/mcp/` over loopback to port 8001, with buffering disabled for SSE.
  The sidecar uses `BACKEND_URL=http://127.0.0.1:8000`; no additional egress is needed.
- Out-of-band Secret `homelable-mcp` must contain two distinct random values:
  `MCP_API_KEY` (client-facing) and `MCP_SERVICE_KEY` (sidecar/backend only).
  Create it via stdin with `kubectl create -f -`, not secret-bearing CLI arguments.
  Preserve existing keys on reruns. Never commit values or last-applied annotations.
- Clients send `X-API-Key` containing `MCP_API_KEY`. Retrieve only in a private terminal:

  ```sh
  kubectl -n homelable get secret homelable-mcp -o jsonpath='{.data.MCP_API_KEY}' | base64 -d
  ```

- This key grants upstream MCP read AND write tools, including topology changes
  and document edits. It is not a read-only integration. Treat imported document
  content as data, not agent instructions. Do not give untrusted agents this key.
- No agent client is automatically registered by deploying the endpoint.
- Public documentation sharing (`DOCS_VIEW_KEY`) and UniFi scheduled sync remain
  explicitly disabled; existing Proxmox settings and outbound restrictions remain.
- Verification: missing/wrong API key must return 401; authenticated initialize,
  tools/list, list_documentation and read_document must succeed through HTTPS.
  Check original canvas/inventory/document counts and SQLite integrity after upgrade.
- Backup: use SQLite's online backup API for a consistent database, archive the
  complete data directory (including uploads), and back up application, Proxmox,
  and MCP Secrets to a private off-pod directory before upgrading. Verify the copy
  with `PRAGMA integrity_check`. No automated backup schedule is implied.
- Rollback: revert the upgrade commit through GitOps. If a schema rollback is
  needed, coordinate stopping writes/reconciliation and restore the matching
  pre-upgrade SQLite backup, uploads and Secrets before starting the old image;
  never blindly downgrade against a migrated database or delete the PVC.

## Verified upstream images

- `ghcr.io/pouzor/homelable-mcp:3.5.0@sha256:811dcf1e463c1945c697fbb358c6489ab496ffc00c36f48a1e63e77df3cca5be`

- `ghcr.io/pouzor/homelable-backend:3.5.0@sha256:64452d231e3227af54ea4e126850cdd6a89b2b169d22bd345e212986ba7621df`
- `ghcr.io/pouzor/homelable-frontend:3.5.0@sha256:c5adb1ce2781345140d2c85d3120ae92cb35c0958cf9664cd2a7207089fb4327`

## Sources (stable release + registry verified)

- https://github.com/Pouzor/homelable/releases/tag/v3.5.0
- https://github.com/Pouzor/homelable/blob/v3.5.0/docker-compose.prebuilt.yml
- https://github.com/Pouzor/homelable/blob/v3.5.0/backend/app/core/config.py
