# Homelable 3.4.2

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
MCP is not deployed and MCP service auth is explicitly empty/disabled. Live view and
Homepage unauthenticated API keys are disabled. Scanner ranges are empty, HTTP
probes/service checks and Proxmox/MQTT sync are off. A deny-all **egress** NetworkPolicy
prevents actual network scanning/status checks even if UI settings are changed.
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
  usage. Resource limits are conservative trial limits, not upstream guarantees.

No host networking, privilege escalation, Linux capabilities, host mounts, Docker
socket, Kubernetes token, remote SSH keys, or Proxmox credentials are supplied.
All containers run as UID/GID 1000 with RuntimeDefault seccomp.

## Verified upstream images

- `ghcr.io/pouzor/homelable-backend:3.4.2@sha256:b6d122e9879a3ade4680a21d0cae485f2382c3e9eecdf8ae1aa8a0a59642f6f0`
- `ghcr.io/pouzor/homelable-frontend:3.4.2@sha256:d9115568828e4b72a1960d64936fa92bedd2d9a00ff133b8efc98c7cc0fb0c9d`

## Sources (stable release + registry verified)

- https://github.com/Pouzor/homelable/releases/tag/v3.4.2
- https://github.com/Pouzor/homelable/blob/v3.4.2/docker-compose.prebuilt.yml
- https://github.com/Pouzor/homelable/blob/v3.4.2/backend/app/core/config.py
