# hledger-web

Plain-text accounting UI ([hledger-web](https://hledger.org/hledger-web.html)). Image: `dastapov/hledger:1.52.3` (the Docker image [hledger.org recommends](https://hledger.org/install.html)). Stock **light** UI — the app has no built-in dark mode.

Public at **https://hledger.homelab.krymancer.dev** (Cloudflare, same as other `*.homelab` apps). `hledger-web` has no password or Basic Auth; `--allow` only limits what a visitor can do (`view` / `add` / `edit`). This instance uses `add` (view + append transactions). Put Traefik basic-auth middleware in front later if you want a login prompt.

Journal data lives on PVC `hledger-data` at `/data/hledger.journal`. An empty starter file is copied there only if the path is missing.

## Import an existing `.journal`

Copy a local file onto the PVC (overwrites the starter). If the journal `include`s other files, copy the whole directory so relative paths still work:

```bash
kubectl -n hledger cp ./my.journal deploy/hledger:/data/hledger.journal

# directory of journals / includes
kubectl -n hledger cp ./journals/. deploy/hledger:/data/

# optional: point HLEDGER_JOURNAL_FILE at another filename, then
kubectl -n hledger rollout restart deploy/hledger
```

hledger-web reloads files on the next page load. To enable upload/download from the UI instead, set `HLEDGER_ALLOW=edit` in the Deployment.

## Backup

The PVC is the source of truth. On edits, hledger-web also writes numbered backups next to the journal (e.g. `hledger.journal.1`). Pull a copy out when you want an off-cluster backup:

```bash
kubectl -n hledger cp deploy/hledger:/data/hledger.journal ./hledger.journal.bak
```
