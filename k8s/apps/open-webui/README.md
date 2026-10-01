# Open WebUI

Chat UI at https://webui.homelab.krymancer.dev. The Ollama API on Proxmox host
`alt` is published at https://ollama.homelab.krymancer.dev.

Both names are private Pi-hole records for the k3s ingress (`192.168.0.20`),
TLS is the existing `homelab-wildcard-tls` certificate, and Traefik `lan-only`
allows `192.168.0.0/24`, Tailscale `100.64.0.0/10`, and subnet-router SNAT
`10.42.0.0/24`. Do not add a Cloudflare Tunnel or a public port forward.
`llm.homelab.krymancer.dev` stays CLIProxyAPI; this app does not replace it.

## How Open WebUI reaches Ollama

There is no Ollama pod. CT **231** `ollama` on alt is already running, with the
RTX 2060 passed through on the Proxmox host, listening on `0.0.0.0:11434`.
The model already loaded there is `qwen2.5-coder:14b`.

`Service/ollama` has no selector. `Endpoints/ollama` pins `192.168.0.23:11434`.
The Deployment sets:

```text
OLLAMA_BASE_URL=http://ollama.open-webui.svc.cluster.local:11434
```

That is the native Ollama API (`/api/...`). Open WebUI does not go out through
the public hostname to talk to the model. Leave `K8S_FLAG` unset. When that
variable is set, Open WebUI rewrites `OLLAMA_BASE_URL` to
`ollama-service.open-webui.svc.cluster.local` and ignores the value above.

https://ollama.homelab.krymancer.dev proxies the same CT port. OpenAI-compatible
clients use base URL `https://ollama.homelab.krymancer.dev/v1` and model
`qwen2.5-coder:14b`. Ollama does not check the API key; the LAN allowlist is
the control. Send any non-empty placeholder the client requires.

The image is the standard multi-arch build, not `:ollama` and not `:cuda`.
Inference stays on the CT. Terraform's RTX 2060 VM scaffold (`enable_gpu_vm`,
default off) is a different guest and is not this CT.

`192.168.0.23` is also the default address of staging k3s VM 220
(`k3s_alt_vm` in `terraform/variables.tf`). Do not boot that VM on this
address while CT 231 owns it.

## Secret

Create this after the namespace exists. Do not commit the values. The pod
stays in `CreateContainerConfigError` until the Secret is present.

```bash
kubectl create secret generic open-webui \
  --namespace open-webui \
  --from-literal=WEBUI_SECRET_KEY="$(openssl rand -hex 32)" \
  --from-literal=WEBUI_ADMIN_EMAIL='admin@homelab.krymancer.dev' \
  --from-literal=WEBUI_ADMIN_PASSWORD='<strong-password>'
```

`WEBUI_SECRET_KEY` must stay stable across upgrades; changing it logs every
session out. On first start, if the database has no users, Open WebUI creates
the admin from `WEBUI_ADMIN_EMAIL` / `WEBUI_ADMIN_PASSWORD` and stores signup
as disabled. `ENABLE_SIGNUP=false` is also set in the Deployment. Later edits
to the password key do not reset an existing user. Changing the email's
password is done in the UI.

Copy the password straight into a password manager. Do not print the Secret.

## Apply

Merge to `main`. The production app-of-apps syncs `k8s/argocd/apps/open-webui.yaml`
(automated, self-heal). That Application creates the namespace and applies
`k8s/apps/open-webui/`. Pi-hole picks up the two names from
`k8s/apps/pihole/configmap.yaml`. Homepage picks up the AI group from its
ConfigMap.

`open-webui` is on the Reflector allowlist in
`k8s/apps/cert-manager/wildcard-cert.yaml`. `secretTemplate` is copied onto
`default/homelab-wildcard-tls` on the next issue. If the live Secret is still
missing `open-webui` in `reflection-allowed-namespaces` and
`reflection-auto-namespaces`, add that namespace to both annotations on the
live Secret once. Do not print the Secret: `kubectl.kubernetes.io/last-applied-configuration`
can contain the private key.

Then:

```bash
kubectl -n open-webui rollout status deploy/open-webui
curl --fail --show-error https://webui.homelab.krymancer.dev/health
curl --fail --show-error https://ollama.homelab.krymancer.dev/api/tags
```

Sign in at https://webui.homelab.krymancer.dev with the admin email. The model
list should include `qwen2.5-coder:14b`. SQLite and uploads live on
`open-webui-data` (5Gi, `local-path`, not pruned by Argo). That PVC is
node-local. Back it up with the Secret if you need to restore the instance.

The CT itself (packages, GPU mounts, the pulled model) was created on alt
outside this repo and is not re-applied by Terraform. Replacing it means
losing the running GPU setup. The contract this repo owns is the Endpoint
address, the two hostnames, and Open WebUI.
