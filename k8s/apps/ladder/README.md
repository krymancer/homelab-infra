# Ladder

HTTP proxy for testing paywall/CORS/HTML modifications, available at
https://ladder.homelab.krymancer.dev through LAN DNS and Tailscale access.

## Access policy

Basic Auth is intentionally disabled (`USERPASS` is not configured). The operator
confirmed there are no public router port forwards for homelab web access.
The deployed Cloudflare Tunnel configuration does not route Ladder, and public
DNS did not resolve this hostname when the policy was checked. A Cloudflare-managed
domain and a publicly trusted TLS certificate do not themselves expose the service.

This trusts clients with LAN/tailnet access. Do not expose the proxy through a
public tunnel, router port forward, or other public ingress without adding
access control first. Private DNS alone is not an access-control boundary.

## Re-enable Basic Auth

The existing `ladder-auth` Secret is retained for rollback. Restore this environment
entry in the Git-managed Deployment and let Argo CD roll out the change:

```yaml
- name: USERPASS
  valueFrom:
    secretKeyRef:
      name: ladder-auth
      key: userpass
```

Provision or rotate the Secret separately if needed; never commit its value.
Do not use an optional Secret reference when Basic Auth is required: a missing
Secret must prevent startup rather than silently disabling authentication.
