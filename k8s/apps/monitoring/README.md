# Monitoring (Grafana / Prometheus)

kube-prometheus-stack is a **one-shot Helm release** named `kube-prom` in namespace `monitoring` (chart **83.4.2**). It is **not** an Argo Application: wrapping that release would fight the existing Helm secret, PVCs, and operator-owned CRs.

GitOps covers **extras only** (exporters, Probe/ServiceMonitor CRs, dashboard ConfigMaps) via Application `monitoring` → `k8s/apps/monitoring/extras`. Helm values for the stack live here as `values.yaml` and are applied with `helm upgrade`.

Grafana login stays chart default **`admin` / `admin`** (do not change it in this tree). Datasource UID is `prometheus` (`grafana.sidecar.datasources.uid`).

The daily driver is Homepage at [https://home.homelab.krymancer.dev](https://home.homelab.krymancer.dev). Grafana’s home dashboard is the **Alt / Homelab Host** overview (`alt-homelab-host`), not a replacement for Homepage.

## Apply order

1. Create the PVE exporter secret (below).
2. `helm upgrade` so mixin dashboards drop and host/PVE scrape jobs exist.
3. Merge/push so Argo syncs `extras/` (or `kubectl apply` that directory).

Uptime Kuma and Pi-hole are untouched.

## Helm upgrade (`values.yaml`)

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade kube-prom prometheus-community/kube-prometheus-stack \
  --namespace monitoring --version 83.4.2 \
  -f k8s/apps/monitoring/values.yaml
```

What this values file changes vs a stock chart:

- `grafana.defaultDashboardsEnabled: false` — no kube-prometheus mixin dashboards
- `grafana.grafana.ini.dashboards.default_home_dashboard_path` — Grafana home is **Alt / Homelab Host** (see Dashboards below)
- Grafana persistence + NodePort **30900**, Prometheus NodePort **30901** (unchanged)
- `additionalScrapeConfigs`: alt `node_exporter` at `192.168.0.11:9100` (job `node-exporter-alt`); PVE API via `pve-exporter.monitoring.svc:9221` `/pve?target=192.168.0.11` (job `pve`)
- Hermes `192.168.0.22:9100` scrape is **commented** until that exporter exists

Probe / ServiceMonitor objects in `extras/` use label `release: kube-prom` so the operator’s default selectors pick them up.

## Secret: `pve-exporter`

Do **not** commit tokens. On **alt** (`https://192.168.0.11:8006`), create a read-only API token (PVEAuditor is enough for guest CPU/mem):

```bash
pveum user add prometheus@pam
pveum aclmod / -user prometheus@pam -role PVEAuditor
pveum user token add prometheus@pam exporter --privsep=0
```

Then on the k3s API (from a machine that can reach the cluster):

```bash
kubectl -n monitoring create secret generic pve-exporter \
  --from-literal=user='prometheus@pam' \
  --from-literal=token_name='exporter' \
  --from-literal=token_value='PASTE-TOKEN-UUID'
```

Keys must be `user`, `token_name`, `token_value`. The Deployment sets `PVE_VERIFY_SSL=false` because alt uses a typical self-signed PVE cert. Secret refs are optional so the pod can schedule before the secret exists; PVE panels stay empty until the secret is present and the pod is restarted/rolled if env was empty at start:

```bash
kubectl -n monitoring rollout restart deploy/pve-exporter
```

## node_exporter on alt (out of cluster)

Installer is **out of scope** for the Git PR. Assume it will listen on **`192.168.0.11:9100`**. On alt:

```bash
apt-get update && apt-get install -y prometheus-node-exporter
# If it is localhost-only, set in /etc/default/prometheus-node-exporter:
#   ARGS="--web.listen-address=:9100"
# then: systemctl restart prometheus-node-exporter
ss -lntp | grep 9100
```

Allow **9100/tcp** from the k3s VM (`192.168.0.20`) if the PVE firewall is on. Optional later: same package on Hermes (`192.168.0.22:9100`), then uncomment the scrape job in `values.yaml` and helm-upgrade again.

## Exporters in `extras/`

| Workload | What it does |
|----------|----------------|
| `blackbox-exporter` | HTTP + DNS modules. **No ICMP** (would need `CAP_NET_RAW`; skipped). |
| Probe `blackbox-http` | job `blackbox_http` → `https://1.1.1.1`, `https://google.com` |
| Probe `blackbox-dns-*` | jobs `blackbox_dns_google` / `blackbox_dns_cloudflare` → A lookup via `1.1.1.1` |
| `speedtest-exporter` | `ghcr.io/ishioni/speedtest-exporter:0.2.5` (Ookla CLI). Cache **45m**, ServiceMonitor interval **45m**, timeout **120s**. Metric names match the Internet dashboard. |
| `pve-exporter` | `prompve/prometheus-pve-exporter:3.10.0` against `https://192.168.0.11:8006` |

## Dashboards (ConfigMaps `grafana_dashboard=1`, folder Homelab)

Sidecar loads these after Grafana is up. Folder annotation is `grafana_folder: Homelab` (enabled in `values.yaml`).

Grafana home (the `/` landing dashboard after login) is **Alt / Homelab Host**. Chart **83.4.2** uses Grafana subchart **11.6.1**, which documents `sidecar.dashboards.folder: /tmp/dashboards` and passes `grafana.ini` through. Combined with sidecar **2.6.0** joining the relative `grafana_folder` annotation, that file is:

`/tmp/dashboards/Homelab/alt-homelab-host.json`

That path is set in `values.yaml` as `grafana.grafana.ini.dashboards.default_home_dashboard_path` so it survives `helm upgrade`. It is the server default when org/user prefs do not already pin a home dashboard.

If the Grafana PVC already stored a different org home, `grafana.ini` does not override it. After the sidecar has imported UID `alt-homelab-host`, patch org prefs (does not change the admin password):

```bash
curl -sS -X PATCH -u admin:admin \
  -H 'Content-Type: application/json' \
  -d '{"homeDashboardUID":"alt-homelab-host"}' \
  https://grafana.homelab.krymancer.dev/api/org/preferences
```

| Dashboard | UID | Needs |
|-----------|-----|--------|
| **Internet Monitoring** | `internet-monitoring` | Blackbox probes + speedtest. ICMP to `192.168.0.1` is not used. Speedtest panels use `last_over_time(...[2h])` because tests are ~45m apart. |
| **Alt / Homelab Host** | `alt-homelab-host` | `node-exporter-alt` (host CPU/mem/disk/net, RAPL if `node_rapl_*` exists) and job `pve` (`pve_guest_info` / CPU / mem for **hermes** and **k3s**). GPU is omitted while VFIO-bound. |
| **k3s Cluster** | `k3s-cluster` | In-cluster `job="node-exporter"`, `kube-state-metrics`, kubelet cAdvisor (`container_memory_working_set_bytes`). Not the mixin kitchen sink. |

**GPU:** the RTX 2060 is **VFIO-bound** on alt. There are no host `nvidia-smi` / DCGM metrics until the card is unbound or a GPU guest runs a DCGM/nvml exporter. Do not expect those series.

## Quick checks (after apply)

```bash
kubectl -n monitoring get deploy,probe,servicemonitor,cm
# Prometheus UI → Status → Targets: blackbox_*, speedtest-exporter, node-exporter-alt, pve
# Grafana → Homelab folder
```
