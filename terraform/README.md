# Terraform (Proxmox)

Manages VMs and LXCs on two standalone Proxmox hosts. They are **not** a cluster, so this root module uses a default `proxmox` provider for `pve` and an aliased `proxmox.alt` provider for `alt`.

| Host | Role | API | Node name |
|------|------|-----|-----------|
| Dell G15 | k3s VM 200, dev LXC 201, Pi-hole/DNS | `https://192.168.0.10:8006` | `pve` |
| alt | GPU passthrough (later k3s) | `https://192.168.0.11:8006` | `alt` (`alt.homelab.krymancer.dev`, MagicDNS `alt`) |

`alt` currently has **8 GiB RAM**. Do not move k3s, do not create heavy auto-start VMs. A 32 GiB upgrade is expected ~25 Sep–5 Oct 2026; k3s migration is a later tfvars change, not this scaffold.

Pi-hole and DNS stay on the G15 (`pve`) until that RAM arrives. Do not change k8s/Argo manifests for Pi-hole as part of this work.

## Dual-node API tokens

Each host needs its **own** token. Do not reuse the G15 secret on alt.

On each node (as root):

```bash
pveum user add terraform@pam
pveum role add Terraform -privs "Datastore.Allocate Datastore.AllocateSpace Datastore.AllocateTemplate Datastore.Audit Mapping.Audit Mapping.Modify Mapping.Use Sys.Audit Sys.Console Sys.Modify VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.Cloudinit VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Migrate VM.Monitor VM.PowerMgmt"
pveum aclmod / -user terraform@pam -role Terraform
pveum user token add terraform@pam terraform --privsep=0
```

Copy `terraform/terraform.tfvars.example` to `terraform.tfvars` (gitignored) and set:

- `proxmox_api_url` / `proxmox_api_token_*` — G15 (`pve`), default URL `https://192.168.0.10:8006`
- `proxmox_alt_api_url` / `proxmox_alt_api_token_*` — alt, default URL `https://192.168.0.11:8006`

Token ID format is `terraform@pam!terraform`. Never commit `terraform.tfvars`.

If alt tokens are left empty, the `proxmox.alt` alias falls back to the `pve` endpoint so existing G15-only plans still work. Set the alt tokens before `enable_gpu_vm = true`.

## Existing workloads (`pve`)

`k3s` and `dev` stay on `pve`. Their `node_name` is now a variable (`k3s_node_name`, `dev_node_name`) defaulting to `"pve"`. After the 32 GiB upgrade, migration is a tfvars change — do not flip those in this scaffold.

Resource addresses are unchanged (`proxmox_virtual_environment_vm.k3s`, `proxmox_virtual_environment_container.dev`). Do not add an explicit `provider` meta-argument to them.

## GPU passthrough scaffold (`alt`)

Optional, off by default:

```hcl
enable_gpu_vm   = false
gpu_vm_started  = false
```

With `enable_gpu_vm = false`, Terraform does not create anything on alt (no RAM, no disk). With `true` and `gpu_vm_started = false`, it creates a **stopped** q35 + OVMF VM (VMID 300) plus Datacenter PCI mappings. The placeholder is 4 cores / 8 GiB / 64G on `local-lvm` / `vmbr0` — that RAM size will thrash the current 8 GiB host if the VM is started.

PCI (verified on the live host):

- `0000:03:00.0` `[10de:1f03]` GPU, `0000:03:00.1` `[10de:10f9]` HD audio
- IOMMU group 28 is clean (those two functions only)
- Proxmox all-functions form is `hostpci0: 0000:03:00,pcie=1,rombar=1`
- This module attaches the same pair via `hostpci.mapping` (`rtx2060`, `rtx2060-audio`) because bpg/proxmox `hostpci.id` is documented as incompatible with API tokens

`rombar = true` is the usual starting point for consumer NVIDIA. If the guest hits Code 43, dump a vBIOS to `/usr/share/kvm/` and set `rom_file`, or try `rombar = false`.

### Host prep (not managed by Terraform)

Apply on **alt** only. Do not attempt this from Terraform (GRUB/modprobe).

1. Enable VT-d in firmware (already active: DMAR present).
2. Kernel cmdline: `intel_iommu=on iommu=pt` (update GRUB or `/etc/kernel/cmdline` and reboot).
3. Bind the GPU to vfio-pci, for example `/etc/modprobe.d/vfio.conf`:
   `options vfio-pci ids=10de:1f03,10de:10f9`
4. Blacklist `nouveau` (and do not load host `nvidia` if you want exclusive guest use).
5. `update-initramfs -u` (or Proxmox equivalent) and reboot.
6. Confirm: `dmesg | grep -i iommu`, `lspci -nnk -s 03:00` shows `vfio-pci`, group 28 still only those two functions.

The host boots **legacy BIOS**. That is fine; the guest uses q35 + OVMF.

### Enable after 32 GiB RAM

1. Finish host VFIO prep above.
2. Put real `proxmox_alt_api_token_*` values in `terraform.tfvars`.
3. Set `enable_gpu_vm = true`, leave `gpu_vm_started = false`.
4. `terraform apply` — creates mappings + a stopped VM. Attach an installer ISO in the UI (or replace the empty `ide2` cdrom).
5. Start only when you are ready: `gpu_vm_started = true` or start VM 300 in the UI. Do not set `on_boot` until k3s has moved and RAM headroom is confirmed.

k3s stays on `pve` until a later change of `k3s_node_name`.
