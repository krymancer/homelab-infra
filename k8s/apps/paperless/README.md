# Paperless-ngx

Document management at https://paperless.homelab.krymancer.dev.

Stack: `paperless-ngx:3.1.3` + PostgreSQL 16.15 + Redis 7.4.11. Create the
`paperless` Secret **before** the webserver and database will stay healthy.
Refs are `optional: true` so Argo can sync the manifests first.

Generate a secret key, then create the Secret (do not commit these values):

```bash
python3 -c "import secrets; print(secrets.token_urlsafe(64))"

kubectl create secret generic paperless \
  --namespace paperless \
  --from-literal=PAPERLESS_ADMIN_USER='admin' \
  --from-literal=PAPERLESS_ADMIN_PASSWORD='<strong-password>' \
  --from-literal=PAPERLESS_SECRET_KEY='<output-of-token_urlsafe>' \
  --from-literal=PAPERLESS_DBPASS='<strong-db-password>'

kubectl -n paperless rollout restart deploy/postgres deploy/paperless
```

Admin user/password are applied only on first start (existing users are not
reset).

## NAS inbox

Drop documents into `\\\\192.168.0.11\\nas\\paperless\\consume`
(macOS: `smb://192.168.0.11/nas`, then `paperless/consume`). The NAS path
`/mnt/nas/share/paperless/consume` is mounted by NFS at
`/usr/src/paperless/consume`. Polling runs every 10 seconds because remote NFS
writes do not emit local filesystem notifications. Successfully imported files
are removed from this inbox; document data/media remain on the existing PVCs.

NAS prerequisites: the existing `/mnt/nas/share` NFS export allows k3s, and
`paperless/consume` is created with owner/group `nas:nas` and mode `2775`.
The application keeps UID 1000 but uses NAS GID 988 so Samba's forced `nas`
user/group can write files and Paperless can consume/delete them. Do not set
pod `fsGroup` to recursively change NAS permissions.

The original `paperless-consume` PVC is retained, empty at cutover. Rollback:
revert the deployment change in Git to remount that PVC; first preserve any
pending files in the NAS inbox.

Office/email conversion (Tika + Gotenberg) is not included; add later if needed.
Authelia is out of scope for this v1.
