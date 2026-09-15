# hledger-web

Plain-text accounting UI ([hledger-web](https://hledger.org/hledger-web.html)). Image: `dastapov/hledger:1.52.3` (the Docker image [hledger.org recommends](https://hledger.org/install.html)). Stock **light** UI — the app has no built-in dark mode.

Public at **https://hledger.homelab.krymancer.dev** (Cloudflare, same as other `*.homelab` apps). `hledger-web` has no password or Basic Auth; `--allow` only limits what a visitor can do (`view` / `add` / `edit`). This instance uses `add` (view + append transactions). Put Traefik basic-auth middleware in front later if you want a login prompt.

## Journal

The NAS finance share is the source of truth — not a cluster PVC copy. Junior edits `Y:\finance\hledger.journal` (SMB `\\192.168.0.11\nas\finance`). On alt that tree is `/mnt/nas/share/finance`. k3s mounts `192.168.0.11:/mnt/nas/share/finance` at `/data` (ReadWriteMany) so `hledger.journal`, `hledger-includes.journal`, and includes under `data/` / `imports/` all resolve. `HLEDGER_JOURNAL_FILE=/data/hledger.journal`.

Do **not** `kubectl cp` a journal into the pod. hledger-web reloads files on the next page load. On edits it also writes numbered backups next to the journal on the share (e.g. `hledger.journal.1`). To enable upload/download from the UI, set `HLEDGER_ALLOW=edit` in the Deployment.

The k3s node (`192.168.0.20`) needs `nfs-common` so kubelet can mount NFS (already being installed on the node). Samba/NFS exports on alt are out of scope here.

NAS files are owned `nas`/`root`. The pod runs as root so `HLEDGER_ALLOW=add` can append on the RW mount. Do not set `fsGroup` (that would chown the share). If adds fail with Permission denied, the export is likely `root_squash` (uid 0 mapped to nobody); fix uid mapping on alt, not in these manifests.

The old local-path PVC `hledger-data` and seed initContainer are gone. Argo prune drops the unused claim; that copy was never authoritative.
