# Termix 2.7.1

Image uses `ghcr.io/lukegus/termix:release-2.7.1`, the publishing path verified in the
**Termix-SSH/Termix** release workflow (the Helm repository default differs).
SQLite/state on a 2Gi local-path PVC; requests 192Mi / limit 512Mi. Only the web
port 8080 is exposed by ClusterIP/Ingress; internal backend ports stay unexposed.

## Authentication / feature scope

First browser registration becomes administrator. Complete it promptly over the
private hostname, then disable public registration in admin settings. There is no
shipped/default user password and no user created by this bootstrap. Keep the route
private until this first-account claim is completed. `termix-crypto` supplies random
64-hex-character `JWT_SECRET`, `DATABASE_KEY`, `ENCRYPTION_KEY`, and
`INTERNAL_AUTH_TOKEN`; no key values or private credential files are in Git.
Do not regenerate these keys on upgrades; back them up together with the PVC.

`ENABLE_TELEMETRY=false` locks telemetry off; `ENABLE_GUACAMOLE=false` disables
RDP/VNC/Telnet support, so no guacd is deployed. TLS terminates at Traefik;
`ENABLE_SSL=false` avoids internal ACME/self-signed-certificate setup. Trusted proxy
auth is off. SSH/web basics require adding a host deliberately through the UI;
no SSH hosts, remote keys, metrics targets, schedules, MCP, or integrations are
preconfigured. Upstream still starts internal SSH/file-manager/metrics/Docker service
modules, but with no remote credentials/hosts or socket they grant no host access.
No speculative unsupported disable flags or upstream patches are applied.

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

- `ghcr.io/lukegus/termix:release-2.7.1@sha256:931e4ce466f4d29b157eb8d6dcd4d36ee5114495c6edddbb19d4e360e2a60f8d`

## Sources (stable release + registry verified)

- https://github.com/Termix-SSH/Termix/releases/tag/release-2.7.1-tag
- https://github.com/Termix-SSH/Termix/blob/release-2.7.1-tag/docker/docker-compose.yml
- https://github.com/Termix-SSH/Termix/blob/release-2.7.1-tag/src/backend/starter.ts
- https://github.com/Termix-SSH/Termix/blob/release-2.7.1-tag/src/backend/utils/system-crypto.ts
