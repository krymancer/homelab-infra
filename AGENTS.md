# AGENTS.md

Infrastructure-as-code for my homelab: the Proxmox guests via Terraform, and every Kubernetes
workload via ArgoCD app-of-apps on k3s. The fleet as a whole (workstations, SSH, conventions) is
described in the global agent context that the dotfiles repo generates (`~/.claude/CLAUDE.md`,
`~/.codex/AGENTS.md`, ...).

## Topology

One standalone Proxmox host, `alt`, runs everything. There is a single cluster and no staging.

| Guest | IP | What | In Terraform |
|-------|----|------|--------------|
| `alt` (host) | 192.168.0.11 | Proxmox VE, node `alt` | - |
| VM 220 `k3s` | 192.168.0.20 | The cluster: Traefik, ArgoCD, Pi-hole LoadBalancer (LAN DNS) | yes |
| LXC 210 `hermes` | 192.168.0.22 | Debian 13, Tailscale SSH. Holds the Terraform state | yes |
| VM 230 `librae-runner-01` | DHCP | GitHub Actions runner for Librae, one job at a time | no |
| VM 300 `gpu` | - | RTX 2060 passthrough scaffold, off by default | yes (count 0) |

Networking:
- LAN `192.168.0.0/24`. Tailscale subnet router `homelab` (`k8s/apps/tailscale`) advertises it to the tailnet.
- DNS: Pi-hole at `192.168.0.20`. Every `*.homelab.krymancer.dev` name is a record in
  `k8s/apps/pihole/configmap.yaml` pointing at `192.168.0.20` (Traefik).
- TLS: one wildcard cert `*.homelab.krymancer.dev` (cert-manager, Let's Encrypt DNS-01 via Cloudflare)
  in `default/homelab-wildcard-tls`. Reflector mirrors it into the namespaces listed in
  `k8s/apps/cert-manager/wildcard-cert.yaml`.
- Public internet: Cloudflare Tunnel only (`k8s/apps/cloudflared/configmap.yaml`), currently just
  `grafana.krymancer.dev` and `argocd.krymancer.dev`. Everything else is LAN/tailnet only, enforced by
  a per-namespace `lan-only` Traefik middleware (`192.168.0.0/24`, `100.64.0.0/10`, `10.42.0.0/24`).

## Layout

```
k8s/argocd/root.yaml          root Application (syncs k8s/argocd/apps)
k8s/argocd/apps/<app>.yaml    one Application per app
k8s/apps/<app>/               plain manifests (or kustomization) for that app
k8s/apps/ingress/             ingresses for apps without their own ingress.yaml
k8s/apps/monitoring/          values.yaml = kube-prom Helm release (NOT Argo-synced); extras/ is synced
terraform/                    Proxmox guests on alt; read terraform/README.md first
```

Most Applications point at this repo's `main`. `discord-bot` and `pjc-artifact-syncer` pull manifests
from their own repos.

## How changes reach the cluster

- ArgoCD auto-syncs `main` with `prune` and `selfHeal`. Merging to `main` deploys. Manual `kubectl
  apply/edit/delete` on repo-managed objects gets reverted. Change the manifests instead.
- Runtime actions are fine: `rollout restart`, deleting a stuck pod, reading logs.
- Own apps (compass, car-info) are built in their repos. Their CI commits `Deploy <App> <sha>` here,
  bumping the image digest in `k8s/apps/<app>/workloads.yaml`. Don't edit those digests by hand.
- Third-party images are pinned (digest or exact tag) and bumped in batches (`chore: bump app images`).
- `k8s/apps/monitoring/values.yaml` is applied with `helm upgrade kube-prom` (command in the file).
- The live ArgoCD was installed from upstream `install.yaml`, not the Terraform Helm release.

## Adding an app

Copy the shape of an existing app (e.g. `k8s/apps/compass`, `k8s/apps/glance`):

1. `k8s/apps/<app>/`: `namespace.yaml`, deployment (pinned image, resource requests and limits),
   `service.yaml`, `pvc.yaml` (local-path, RWO) if stateful.
2. Ingress: host `<app>.homelab.krymancer.dev`, `ingressClassName: traefik`, entrypoint `websecure`,
   `tls.secretName: homelab-wildcard-tls`, middleware `<ns>-lan-only@kubernetescrd` with a `lan-only`
   Middleware in the namespace.
3. `k8s/argocd/apps/<app>.yaml` (with `CreateNamespace=true`).
4. Add the namespace to **both** reflector lists in `k8s/apps/cert-manager/wildcard-cert.yaml`.
5. Add `192.168.0.20 <app>.homelab.krymancer.dev` to `k8s/apps/pihole/configmap.yaml`.
6. Optionally add a launcher entry to `k8s/apps/glance/configmap.yaml`.

## Secrets

Never commit real secrets. The repo carries `*-secret.example.yaml` / `config.example.txt` templates
and bootstrap scripts (`provision-secrets.py`, `bootstrap-secrets.py`). Real Secrets are created with
`kubectl` and live only in the cluster. `terraform.tfvars`, `*.tfstate` and `terraform/.kube/` are
gitignored. Keep it that way.

## Guardrails

- The cluster is live and there is nowhere else to test. Prefer small changes that are easy to revert.
- Terraform: run it only from the LAN (the state lives on `hermes`), never from a cloud agent. Show
  `terraform plan` and get approval before `apply`. Stop if a plan replaces or destroys VM 220 or
  LXC 210. `-replace` on `proxmox_virtual_environment_vm.k3s` reinstalls it and **destroys the cluster**.
- Keep `bootstrap = false` against the live guests. It is for from-scratch builds and would overwrite
  hermes `authorized_keys` and re-run `tailscale up`.
- VM 230 (the Librae runner) is not in Terraform, so a plan saying nothing about it is expected.
- Persistence is not backup. Don't delete PVCs, TSDB/WAL data or app databases to free space.
- Many app READMEs (`k8s/apps/<app>/README.md`) document resource budgets and pinned versions. Read
  the app's README before changing it.

## Checking live state

```sh
export KUBECONFIG=~/.kube/config-k3s          # the cluster (192.168.0.20)
kubectl -n argocd get applications            # sync/health of every app
kubectl -n <app> get pods,svc,ingress,pvc
kubectl -n <app> logs deploy/<name> --tail=200
ssh root@alt qm list; ssh root@alt pct list   # Proxmox guests
```
