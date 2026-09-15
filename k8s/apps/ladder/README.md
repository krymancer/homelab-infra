# Ladder

HTTP proxy for testing paywall/CORS/HTML modifications. Public at https://ladder.homelab.krymancer.dev.

The instance is on a public Cloudflare hostname, so Basic Auth is required. `USERPASS` is optional so Argo can sync before the secret exists, but the pod needs the secret to enable auth (roll the Deployment after creating it):

```bash
kubectl create secret generic ladder-auth \
  --namespace ladder \
  --from-literal=userpass='admin:<password>'

kubectl -n ladder rollout restart deploy/ladder
```
