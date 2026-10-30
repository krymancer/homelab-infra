# Home Assistant

UI at https://ha.homelab.krymancer.dev. Merge to `main`. The production and
staging app-of-apps both sync `k8s/argocd/apps/home-assistant.yaml` (automated,
self-heal). That Application creates the namespace and applies this directory.
Pi-hole picks up the name from `k8s/apps/pihole/configmap.yaml`. Glance picks
up the Apps monitor group from its ConfigMap.

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

`TZ=America/Sao_Paulo` matches Pi-hole. That zone is UTC−3
year-round, the same offset as `America/Fortaleza`.

## Cloud sign-in

SmartThings and Tuya are core integrations. The seed already has what their
sign-in needs.

SmartThings 2026.10 aborts setup unless the `cloud` component is loaded.
`default_config` loads `cloud` and `my`. The sign-in is Home Assistant Cloud
account linking (`smartthings` on `account-link.nabucasa.com`). The browser
goes to Samsung, and the pod receives the tokens on an outbound websocket.
A Nabu Casa subscription is not part of that link. Samsung is phasing out
free API access; a Personal Plan may be required. See the integration page.

Tuya asks for the User Code from the Smart Life or Tuya Smart app and shows
a QR code for that app to scan. The pod calls Tuya's cloud. The sign-in
stays in the app.

`use_x_forwarded_for` and `trusted_proxies` stay so Traefik's
`X-Forwarded-For` does not make the UI return HTTP 400 while those flows
are used. `homeassistant.external_url` is not set. These flows do not call
back to the ingress, and a `homeassistant:` block marks core config as YAML
and locks General settings that onboarding writes from the UI.

Both flows need outbound HTTPS from the pod. No NetworkPolicy selects this
pod. The only NetworkPolicy in the repo is `homelable`'s, and its pod
selector is `app: homelable`.

## Custom components

HACS `2.0.5` and `greghesp/ha-bambulab` `v2.2.26` are pinned in
`custom-components.yaml` (sha256 of `hacs.zip` and `bambu_lab.zip`). Those
were the latest stable GitHub releases when this was added. HACS `2.0.5`
(2025-01-28) is still the newest tag that is not a prerelease.

The `install-custom-components` init container runs before Home Assistant.
It downloads a release only when `/config/custom_components/<domain>` is
missing or its `manifest.json` version does not match the pin, checks
sha256, and extracts that directory. A later start skips a component that
still matches. It does not rewrite `configuration.yaml`, `.storage`, or any
other custom component. Pins live in `/config/.custom-component-pins/`.

Change the pin in git to upgrade. An upgrade done from the HACS UI is
replaced on the next pod start once the manifest version no longer matches.

The first start needs GitHub reachable from the pod. After the files are on
the PVC, a restart does not download them again. HACS is not active until
it is added in the UI. Bambu Lab is listed as an integration without a
separate HACS download.

## Discovery

This pod is not on `hostNetwork` and has no extra network capabilities. No
other app in this repo uses `hostNetwork`. Pi-hole publishes DNS with a
LoadBalancer on `192.168.0.20`; this Service stays ClusterIP and does not take
that address.

mDNS (UDP 5353) and SSDP (UDP 1900) are link-local, so they do not cross from
the pod network onto the LAN. Devices will not auto-discover. Add them by IP
in the UI. The install is reached through Traefik at
https://ha.homelab.krymancer.dev.

Bambu Lab's SSDP search (`urn:bambulab-com:device:3dprinter:1`) will not see
the printer. Add it by hand: printer IP, serial number, and LAN access code.
Bambu Lab cloud login is the other path, for an account that has a password.

LAN mode opens outbound MQTT TLS on TCP `8883` and implicit FTPS on TCP
`990` to the printer on `192.168.0.0/24`. Camera and file cache may also
open TCP `6000`. Nothing in these manifests blocks that. `lan-only` is
inbound HTTP on the Ingress. There is no egress NetworkPolicy on
`home-assistant`.

## Adding the integrations

Open https://ha.homelab.krymancer.dev. Create the owner account first if
this is a new PVC.

### HACS

The files are already in `custom_components/hacs`. This only activates them.

1. Settings > Devices & services > Add integration > HACS.
2. Accept the acknowledgements and submit.
3. Complete the GitHub device login in the browser.
4. Skip downloading Bambu Lab from HACS. That release is already on disk.
   Do not upgrade HACS or Bambu Lab from the HACS UI. Change the pin in
   `custom-components.yaml` instead.

### SmartThings

1. Settings > Devices & services > Add integration > SmartThings.
2. Sign in with the Samsung account that owns the devices and approve
   access. Leave the Home Assistant tab open until the account link
   finishes.
3. The location's devices show up on the integration. No developer app and
   no redirect URL are entered here.

### Tuya

The devices have to be in the Smart Life or Tuya Smart app first.

1. In the app: Me > gear > Account and Security. Copy the User Code at the
   bottom.
2. Settings > Devices & services > Add integration > Tuya.
3. Enter the User Code. A QR code is shown.
4. In the app, add a device and choose the QR scanner. Scan the code on the
   Home Assistant screen, then submit.
5. After adding more devices in the app, reload Tuya from the integration's
   menu so they appear.

### Bambu Lab

The printer has to be on `192.168.0.0/24`, reachable from the cluster. In
the printer's network settings, turn on LAN mode and note the access code.
The serial number is in the printer's device settings.

1. Settings > Devices & services > Add integration > Bambu Lab.
2. For a printer that stays on LAN only, choose Lan Mode. Enter the IP,
   serial number, and access code. SSDP will not fill these in.
3. Otherwise choose Bambu Lab cloud. Pick the account region and sign in
   with email or phone and a password. A social login with no password will
   not work; set a password in the Bambu Lab app first (Account Security >
   Change Password). If Bambu asks, enter the email or 2FA code. Then pick
   the printer. Cloudflare sometimes blocks this cloud login; use Lan Mode
   in that case.

## Apply

```bash
kubectl -n home-assistant rollout status deploy/home-assistant
curl --fail --show-error https://ha.homelab.krymancer.dev/
```

Open https://ha.homelab.krymancer.dev and create the owner account. Config and
the recorder database live on `home-assistant-config` (5Gi, `local-path`, not
pruned by Argo). That PVC is node-local. Back it up before an image upgrade
if you need to restore the instance. The image is pinned to `2026.10.0`, the
same digest as the `stable` tag at the time it was added.
