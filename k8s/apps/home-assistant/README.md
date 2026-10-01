# Home Assistant

UI at https://ha.homelab.krymancer.dev. Merge to `main`. The production and
staging app-of-apps both sync `k8s/argocd/apps/home-assistant.yaml` (automated,
self-heal). That Application creates the namespace and applies this directory.
Pi-hole picks up the name from `k8s/apps/pihole/configmap.yaml`. Homepage picks
up the Apps group from its ConfigMap.

The name is a private Pi-hole record for the k3s ingress (`192.168.0.20`).
TLS is the existing `homelab-wildcard-tls` certificate. Traefik `lan-only`
allows `192.168.0.0/24`, Tailscale `100.64.0.0/10`, and subnet-router SNAT
`10.42.0.0/24`. Do not add a Cloudflare Tunnel or a public port forward.

`home-assistant` is on the Reflector allowlist in
`k8s/apps/cert-manager/wildcard-cert.yaml`. `secretTemplate` is copied onto
`default/homelab-wildcard-tls` on the next issue. If the live Secret is still
missing `home-assistant` in `reflection-allowed-namespaces` and
`reflection-auto-namespaces`, add that namespace to both annotations on the
live Secret once. Do not print the Secret: `kubectl.kubernetes.io/last-applied-configuration`
can contain the private key.

There is no app Secret. The first visit to the UI creates the owner account.
Do not commit that password.

## Proxy and timezone

Home Assistant 2026.9 returns HTTP 400 when `X-Forwarded-For` is present and
the HTTP integration does not trust the proxy. Traefik always sends that
header. An init container copies `home-assistant-seed` to
`/config/configuration.yaml` only when the file is missing. That seed trusts
the k3s pod CIDR `10.42.0.0/16` (Traefik's pod address) plus loopback. Later
edits stay on the PVC; changing the ConfigMap does not rewrite an existing
file.

`TZ=America/Sao_Paulo` matches Pi-hole and Open WebUI. That zone is UTC−3
year-round, the same offset as `America/Fortaleza`.

## Discovery

This pod is not on `hostNetwork` and has no extra network capabilities. No
other app in this repo uses `hostNetwork`. Pi-hole publishes DNS with a
LoadBalancer on `192.168.0.20`; this Service stays ClusterIP and does not take
that address or `192.168.0.23` (Ollama CT 231).

mDNS (UDP 5353) and SSDP (UDP 1900) are link-local, so they do not cross from
the pod network onto the LAN. Devices will not auto-discover. Add them by IP
in the UI. The install is reached through Traefik at
https://ha.homelab.krymancer.dev.

## Apply

```bash
kubectl -n home-assistant rollout status deploy/home-assistant
curl --fail --show-error https://ha.homelab.krymancer.dev/
```

Open https://ha.homelab.krymancer.dev and create the owner account. Config and
the recorder database live on `home-assistant-config` (5Gi, `local-path`, not
pruned by Argo). That PVC is node-local. Back it up before an image upgrade
if you need to restore the instance. The image is pinned to `2026.9.4`, the
same digest as the `stable` tag at the time it was added.
