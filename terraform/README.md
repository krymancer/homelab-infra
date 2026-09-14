# Terraform (Proxmox)

Manages VMs and LXCs on two standalone Proxmox hosts. They are **not** a cluster, so this root module uses a default `proxmox` provider for `pve` and an aliased `proxmox.alt` provider for `alt`.

| Host | Role | API | Node name |
|------|------|-----|-----------|
| Dell G15 | k3s VM 200 (production), Pi-hole/DNS | `https://192.168.0.10:8006` | `pve` |
| alt | Debian LXC `hermes` 210; staging k3s-alt VM 220 (stopped) | `https://192.168.0.11:8006` | `alt` |

Do not attach `provider = proxmox.alt` (or any explicit provider) to the existing `proxmox_virtual_environment_vm.k3s` resource; that would look like a move and could destroy the live cluster.

**Do not apply** the staging k3s VM until Ubuntu cloud-init template **VMID 9000** exists on alt.

## Dual-node API tokens

Each host needs its **own** token. You can reuse the same token *id string* (`terraform@pam!terraform`) if you create it on both nodes. Leave `proxmox_alt_api_token_*` empty to reuse `proxmox_api_token_*` values; set distinct alt secrets when the tokens differ.

On each node (as root):

```bash
pveum user add terraform@pam
pveum role add Terraform -privs "Datastore.Allocate Datastore.AllocateSpace Datastore.AllocateTemplate Datastore.Audit Mapping.Audit Mapping.Modify Mapping.Use Sys.Audit Sys.Console Sys.Modify VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.Cloudinit VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Migrate VM.Monitor VM.PowerMgmt"
pveum aclmod / -user terraform@pam -role Terraform
pveum user token add terraform@pam terraform --privsep=0
```

Copy `terraform.tfvars.example` to `terraform.tfvars` (gitignored). Never commit `terraform.tfvars`.

## Hermes LXC (`alt`)

Unprivileged Debian 13 container, VMID 210, `192.168.0.22/24` on `vmbr0`, disk on datastore `ssd` (zfspool). DNS is Pi-hole on the G15 (`192.168.0.20`) plus `1.1.1.1`. TUN is patched on **alt** (`lxc.cgroup2` + `/dev/net/tun`) so Tailscale can run; `tailscale up` uses `--ssh`.

Debian template on alt (`local:vztmpl/...`). Confirm the exact filename, then download if missing:

```bash
pveam update
pveam download local debian-13-standard
pveam list local
```

If the downloaded filename differs from `debian-13-standard_13.1-2_amd64.tar.zst`, update `hermes_lxc.template` in `terraform.tfvars`.

## Staging k3s VM (`alt`)

`proxmox_virtual_environment_vm.k3s_alt` clones Ubuntu cloud-init template **VMID 9000 on alt** into VMID 220 (`k3s-alt`), 8 cores / 16 GiB / 120G on datastore `ssd`, virtio on `vmbr0`, cloud-init user `junho`.

| | Production (`k3s` on pve) | Staging (`k3s-alt` on alt) |
|--|--|--|
| Resource | `proxmox_virtual_environment_vm.k3s` | `proxmox_virtual_environment_vm.k3s_alt` |
| Provider | default (`pve`) | `proxmox.alt` |
| VMID | 200 | 220 |
| Hostname | `k3s` | `k3s-alt` (avoids clash until cutover) |
| IP | `192.168.0.20/24` | `192.168.0.23/24` |
| DNS | (unchanged) | Pi-hole `192.168.0.20` + `1.1.1.1` |
| Started | live | `started = false`, `on_boot = false` |

Create the Ubuntu cloud template on alt as VMID 9000 **before** `terraform apply`. Apply will fail if that template is missing.

Keep `k3s_alt_started = false` for this prep step. Flip it only when you intend to boot the guest.

### Cutover (later; not this change)

A later cutover will move cluster services off pve VM 200 onto this guest. That may reassign **192.168.0.20** (Pi-hole/DNS and current k3s) onto alt and drop the `-alt` hostname. Until then, leave production k3s and `.20` on pve so a normal apply does not destroy the live cluster.

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

Host VFIO prep (GRUB `intel_iommu=on iommu=pt`, `vfio-pci` ids `10de:1f03,10de:10f9`, nouveau blacklist) is **not** managed by Terraform. Do not enable this while k3s-alt 16 GiB + hermes are competing for the 32 GiB host unless you have confirmed headroom. The Terraform role needs `Mapping.Audit Mapping.Modify Mapping.Use` for the PCI mappings.
