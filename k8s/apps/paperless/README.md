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
reset). Drop files into the consume PVC (`paperless-consume`) to import them.

Office/email conversion (Tika + Gotenberg) is not included; add later if needed.
Authelia is out of scope for this v1.
