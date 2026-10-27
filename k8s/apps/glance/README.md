# Glance

Dashboard at https://home.homelab.krymancer.dev (replaced Homepage). Image
`glanceapp/glance:v0.8.7`, pinned by index digest. LAN/Tailscale only via the
`lan-only` middleware.

## Pages

- **Home**: four monitor groups (Infrastructure, Apps, Media, Tools &
  Security), host-health bars for alt and the k3s node, Pi-hole stats, links.
- **Feeds**: clock, calendar, Hacker News, selfh.st, GitHub releases of the
  main apps.

## Editing

All config lives in `configmap.yaml` (`glance.yml`). The ConfigMap is mounted
as a directory (no `subPath`), so a synced change reaches the pod in about a
minute and Glance reloads it without a restart. Validate locally first:

```bash
kubectl create --dry-run=client -o jsonpath='{.data.glance\.yml}' \
  -f k8s/apps/glance/configmap.yaml > /tmp/glance/glance.yml
podman run --rm -e PIHOLE_PASSWORD=x -v /tmp/glance:/app/config:ro \
  docker.io/glanceapp/glance:v0.8.7 --config /app/config/glance.yml config:validate
```

Monitors use `url` for the browser link and `check-url` for an in-cluster
Service, so checks skip Traefik and TLS. A service whose root redirects to its
public hostname needs a `check-url` that points past the redirect, because
`*.homelab.krymancer.dev` does not resolve inside the cluster (see hledger).

Health bars are `custom-api` widgets that query Prometheus
(`kube-prom-kube-prometheus-prometheus.monitoring:9090`). alt metrics come from
the `node-exporter-alt` job and `pve-exporter` (`storage/alt/ssd`).

## Secret

`glance-secrets` is created out of band and never committed:

```bash
kubectl -n glance create secret generic glance-secrets \
  --from-literal=PIHOLE_PASSWORD='<Pi-hole web/app password>'
```

Glance will not start if the Secret or key is missing (`${PIHOLE_PASSWORD}` is
required by the config). Update it when the Pi-hole password changes, then
`kubectl -n glance rollout restart deploy/glance`.
