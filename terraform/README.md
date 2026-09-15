# Terraform (Proxmox)

Manages VMs and LXCs on two standalone Proxmox hosts. They are **not** a cluster, so this root module uses a default `proxmox` provider for `pve` and an aliased `proxmox.alt` provider for `alt`.

| Host | Role | API | Node name |
|------|------|-----|-----------|
| Dell G15 | k3s VM 200 (production), Pi-hole/DNS | `https://192.168.0.10:8006` | `pve` |
| alt | Debian LXC `hermes` 210; staging k3s VM 220 | `https://192.168.0.11:8006` | `alt` |

Do not attach `provider = proxmox.alt` (or any explicit provider) to the existing `proxmox_virtual_environment_vm.k3s` resource; that would look like a move and could destroy the live cluster.

**Do not apply this module from a cloud agent against live infra.** Run it from a machine on the LAN (or Hermes) with an SSH agent loaded.

## Replicate from scratch

After Proxmox is installed on the node, `terraform apply` (twice, see Argo below) brings up Hermes, a k3s VM that installs k3s on first boot, and Argo CD pointed at this repo's app-of-apps.

### Still manual (not Terraform)

1. **Install Proxmox VE** on the host. Configure `vmbr0`, a management IP, and storage:
   - `local` (directory): ISO, LXC templates, **snippets**
   - `local-lvm` (LVM-Thin): cloud-init ISO for VMs (zfspool cannot hold that ISO)
   - `ssd` (zfspool on alt): guest disks
2. **Enable snippets** on `local`:
   ```bash
   pvesm set local --content backup,iso,vztmpl,snippets
   ```
3. **Debian 13 LXC template** (Hermes):
   ```bash
   pveam update
   pveam download local debian-13-standard
   pveam list local
   ```
   If the filename differs from `debian-13-standard_13.1-2_amd64.tar.zst`, set `hermes_lxc.template` in `terraform.tfvars`.
4. **Ubuntu cloud-init template VMID 9000** with `qemu-guest-agent` installed and enabled. Apply waits on the guest agent; baking it into the template avoids a long first-boot hang. Cloud-init also installs the agent as a backup. Typical shape: Ubuntu cloud image, cloud-init drive, QEMU guest agent, DHCP or a dummy IP (the clone overwrites network via cloud-init).
5. **Proxmox API tokens** on each node (`terraform@pam!terraform`). See [Dual-node API tokens](#dual-node-api-tokens).
6. **Secrets in `terraform.tfvars`** (copy `terraform.tfvars.example`, gitignored): API token secrets, `ci_password`, `ssh_public_key`, Tailscale auth key, optional GitHub PAT (`argocd_git_token`).
7. **SSH agent** on the Terraform runner with the private key that matches `ssh_public_key`. Hermes bootstrap SSHes to the Proxmox host (`pct exec`); k3s kubeconfig fetch SSHes to `192.168.0.23`.
8. **Tailscale pre-auth key** at [login.tailscale.com/admin/settings/keys](https://login.tailscale.com/admin/settings/keys) (Hermes `tailscale up`).
9. Optional: GitHub PAT if Argo must clone private repos or you hit GitHub rate limits.

### What `terraform apply` does

| Layer | How |
|-------|-----|
| Hermes LXC 210 | Clone Debian template, network, TUN device on the alt host, packages, Tailscale (`--ssh`) |
| Cloud-init snippet | Upload `cloud-init/k3s-alt-user-data.yaml.tftpl` to `local:snippets/` |
| k3s VM 220 | Clone template 9000, LAN `192.168.0.23/24`. **First boot** installs `qemu-guest-agent` + k3s (`tls-san` / `node-ip` = `.23`) |
| kubeconfig | SSH wait/retry, write `terraform/.kube/k3s-alt.yaml` (gitignored) |
| Argo CD | Helm release `argo-cd` into namespace `argocd` (second apply) |
| Root Application | Points at `k8s/argocd/apps` in this repo; staging excludes Pi-hole and cloudflared until cutover |

Production VM 200 on pve is left as-is (clone/network/user only — no k3s/Argo bootstrap on that resource).

### Scratch tfvars flags

```hcl
k3s_alt_started          = true
k3s_alt_bootstrap_argocd = true
argocd_sync_cutover_apps = false
```

Keep `k3s_alt_started = false` on the current homelab until you intend to boot staging.

### Two applies for Argo

The Helm provider needs a kubeconfig at **plan** time. First apply with `k3s_alt_started = true` creates the VM, runs cloud-init, and fetches kubeconfig. Second apply sees `terraform/.kube/k3s-alt.yaml` and installs Argo + the root Application.

```bash
cd terraform
terraform init
terraform apply    # VM + k3s + kubeconfig
terraform apply    # Helm Argo CD + root Application
```

Equivalent: first `terraform apply -target=proxmox_virtual_environment_vm.k3s_alt -target=terraform_data.k3s_alt_kubeconfig`, then a full apply.

## Dual-node API tokens

Each host needs its **own** token. You can reuse the same token *id string* (`terraform@pam!terraform`) if you create it on both nodes. Leave `proxmox_alt_api_token_*` empty to reuse `proxmox_api_token_*` values; set distinct alt secrets when the tokens differ.

On each node (as root):

```bash
pveum user add terraform@pam
pveum role add Terraform -privs "Datastore.Allocate Datastore.AllocateSpace Datastore.AllocateTemplate Datastore.Audit Mapping.Audit Mapping.Modify Mapping.Use Sys.Audit Sys.Console Sys.Modify VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.Cloudinit VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Migrate VM.Monitor VM.PowerMgmt"
pveum aclmod / -user terraform@pam -role Terraform
pveum user token add terraform@pam terraform --privsep=0
```

Copy `terraform.tfvars.example` to `terraform.tfvars` (gitignored). Never commit `terraform.tfvars` or `terraform/.kube/`.

## Hermes LXC (`alt`)

Unprivileged Debian 13 container, VMID 210, `192.168.0.22/24` on `vmbr0`, disk on datastore `ssd` (zfspool). DNS is Pi-hole on the G15 (`192.168.0.20`) plus `1.1.1.1`. TUN is patched on **alt** (`lxc.cgroup2` + `/dev/net/tun`) so Tailscale can run; `tailscale up` uses `--ssh`.

Proxmox LXC cloud-init only covers hostname/user/network, so first-boot packages and Tailscale stay `pct`/SSH provisioners (not a guest `user_data` script).

## Staging k3s VM (`alt`)

`proxmox_virtual_environment_vm.k3s_alt` clones Ubuntu cloud-init template **VMID 9000 on alt** into VMID 220 (`k3s`), 8 cores / balloon 8–16 GiB / 120G on datastore `ssd`, virtio on `vmbr0`. The Terraform resource stays `k3s_alt` so it does not collide with production `proxmox_virtual_environment_vm.k3s` on pve; Proxmox VM name is `k3s`.

Clone and scsi0 stay on `ssd` (zfspool). Cloud-init ISO (`initialization.datastore_id`) must be `local-lvm` — Proxmox cannot store that ISO on a zfspool. `initialization.hostname` is not valid on this resource in bpg/proxmox 0.113; hostname is set in the user_data snippet. bpg also rejects `user_account` together with `user_data_file_id`, so SSH user/key/password live in the snippet.

| | Production (`k3s` on pve) | Staging (`k3s` on alt) |
|--|--|--|
| Resource | `proxmox_virtual_environment_vm.k3s` | `proxmox_virtual_environment_vm.k3s_alt` |
| Provider | default (`pve`) | `proxmox.alt` |
| VMID | 200 | 220 |
| Hostname | `k3s` | `k3s` |
| IP | `192.168.0.20/24` | `192.168.0.23/24` |
| DNS | (unchanged) | Pi-hole `192.168.0.20` + `1.1.1.1` |
| k3s / Argo | live, not bootstrapped by this module | cloud-init k3s + Helm Argo when started |
| Started | live | `k3s_alt_started` (default `false`) |

Create the Ubuntu cloud template on alt as VMID 9000 **before** `terraform apply`. Apply will fail if that template is missing. Bake `qemu-guest-agent` into that template (`apt install qemu-guest-agent` and enable the service) so apply does not hang waiting for the guest agent.

### Existing VM 220 (do not destroy by default)

`lifecycle.ignore_changes` includes `initialization`, so adding the cloud-init snippet does **not** replace a VM that is already in state. user_data changes also do not re-run cloud-init on a disk that has already booted.

- Already cloned, never want a recreate: apply is safe; k3s will **not** install from this PR until you replace the VM.
- Want first-boot k3s on that guest: `terraform apply -replace='proxmox_virtual_environment_vm.k3s_alt'` (staging only — not production VM 200).
- Fresh clone (not in state): create uses the snippet; first boot installs k3s.

### Cutover (later; not this change)

A later cutover will move cluster services off pve VM 200 onto this guest. That may reassign **192.168.0.20** (Pi-hole/DNS and current k3s) onto alt. Until then, leave production k3s and `.20` on pve so a normal apply does not destroy the live cluster.

Set `argocd_sync_cutover_apps = true` only when this cluster should sync Pi-hole and cloudflared.

## Staging vs production coexistence

Live DNS/Pi-hole LoadBalancer is **192.168.0.20** on pve VM 200. Staging is **192.168.0.23**. Do not let the parallel cluster claim `.20`.

Staging root Application (`k8s/argocd/staging-root.yaml`, applied by Terraform) syncs `k8s/argocd/apps` with a directory exclude while `argocd_sync_cutover_apps = false`:

| App | Why it stays off staging by default |
|-----|-------------------------------------|
| `pihole.yaml` | `loadBalancerIP: 192.168.0.20` would steal live DNS |
| `cloudflared.yaml` | same tunnel UUID would steal public hostnames |

Add more filenames with `argocd_extra_exclude_app_files` (for example `["tailscale.yaml"]` if you do not want a second subnet router). Production continues to use `k8s/argocd/root.yaml` with no exclude.

After Argo is up:

```bash
export KUBECONFIG=terraform/.kube/k3s-alt.yaml
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
kubectl -n argocd port-forward svc/argocd-server 8080:80
```

Ingress on staging will bind to `.23` (k3s servicelb), not `.20`. Apps that assume live TLS secrets, Cloudflare creds, or Tailscale auth keys will stay degraded until those secrets exist on the new cluster.

## GPU passthrough scaffold (`alt`)

Optional, off by default (`enable_gpu_vm = false` → `count = 0`, nothing created):

```hcl
enable_gpu_vm  = false
gpu_vm_started = false
```

When enabled, Terraform creates Datacenter PCI mappings plus a **stopped** q35 + OVMF VM (VMID 300) on `ssd`. PCI (verified on the live host):

- `0000:03:00.0` `[10de:1f03]` GPU and `0000:03:00.1` `[10de:10f9]` HD audio
- IOMMU group 28 is clean (those two functions only)
- Attached via `hostpci.mapping` (`rtx2060`, `rtx2060-audio`) because bpg/proxmox `hostpci.id` is incompatible with API tokens

Host VFIO prep (GRUB `intel_iommu=on iommu=pt`, `vfio-pci` ids `10de:1f03,10de:10f9`, nouveau blacklist) is **not** managed by Terraform. Do not enable this while staging k3s 16 GiB + hermes are competing for the 32 GiB host unless you have confirmed headroom. The Terraform role needs `Mapping.Audit Mapping.Modify Mapping.Use` for the PCI mappings.
