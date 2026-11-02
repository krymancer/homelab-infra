# car-info

[krymancer/car-info](https://github.com/krymancer/car-info): vehicle cost tracker at https://cars.homelab.krymancer.dev (LAN + Tailscale only).

- CI in car-info pins the image digest in `workloads.yaml` on every push to main.
- `car-info-secrets` (`APP_PASSWORD`) is created by hand: `kubectl -n car-info create secret generic car-info-secrets --from-literal=APP_PASSWORD=...`
- Live data: node-local PVC `car-info-data`. Daily backups: NFS `alt:/mnt/nas/share/data/cars` (must be writable by uid 1000).
