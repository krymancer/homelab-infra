# Terraform (Proxmox)

Manages VMs and LXCs on two standalone Proxmox hosts. They are **not** a cluster, so this root module uses a default `proxmox` provider for `pve` and an aliased `proxmox.alt` provider for `alt`.

| Host | Role | API | Node name |
|------|------|-----|-----------|
| Dell G15 | k3s VM 200, Arch LXC `dev` 201, Pi-hole/DNS | `https://192.168.0.10:8006` | `pve` |
| alt | Debian LXC `hermes` 210 | `https://192.168.0.11:8006` | `alt` |

Do not attach `provider = proxmox.alt` (or any explicit provider) to the existing k3s/dev resources; that would look like a move.

## Dual-node API tokens

Each host needs its **own** token. You can reuse the same token *id string* (`terraform@pam!terraform`) if you create it on both nodes. Leave `proxmox_alt_api_token_*` empty to reuse `proxmox_api_token_*` values; set distinct alt secrets when the tokens differ.

On each node (as root):

```bash
pveum user add terraform@pam
pveum role add Terraform -privs "Datastore.Allocate Datastore.AllocateSpace Datastore.AllocateTemplate Datastore.Audit Sys.Audit Sys.Console Sys.Modify VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.Cloudinit VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Migrate VM.Monitor VM.PowerMgmt"
pveum aclmod / -user terraform@pam -role Terraform
pveum user token add terraform@pam terraform --privsep=0
```

Copy `terraform.tfvars.example` to `terraform.tfvars` (gitignored). Never commit `terraform.tfvars`.

## Hermes LXC (`alt`)

Unprivileged Debian 13 container, VMID 210, `192.168.0.22/24` on `vmbr0`, disk on datastore `ssd` (zfspool). DNS is Pi-hole on the G15 (`192.168.0.20`) plus `1.1.1.1`. TUN is patched on **alt** (same `lxc.cgroup2` + `/dev/net/tun` pattern as `dev`) so Tailscale can run; `tailscale up` uses `--ssh`.

Debian template on alt (`local:vztmpl/...`). Confirm the exact filename, then download if missing:

```bash
pveam update
pveam download local debian-13-standard
pveam list local
```

If the downloaded filename differs from `debian-13-standard_13.1-2_amd64.tar.zst`, update `hermes_lxc.template` in `terraform.tfvars`.
