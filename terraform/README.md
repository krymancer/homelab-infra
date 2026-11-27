# Terraform (Proxmox)

Manages the guests on the standalone Proxmox host `alt` (`https://192.168.0.11:8006`, node `alt`).

| Guest | VMID | IP | Notes |
|-------|------|----|-------|
| `k3s` VM | 220 | `192.168.0.20/24` | The cluster. Pi-hole LoadBalancer and ingress also live on `.20` |
| `hermes` LXC | 210 | `192.168.0.22/24` | Debian 13, Tailscale `--ssh` |
| `gpu` VM | 300 | — | Optional passthrough scaffold, off by default |

**Do not apply this module from a cloud agent against live infra.** Run it from a machine on the LAN (Hermes has the state in `~/repos/homelab-infra/terraform`) with an SSH agent loaded.

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
5. **Proxmox API token** on alt (`terraform@pam!terraform`). See [API token](#api-token).
6. **Secrets in `terraform.tfvars`** (copy `terraform.tfvars.example`, gitignored): API token secrets, `ci_password`, `ssh_public_key`, Tailscale auth key, optional GitHub PAT (`argocd_git_token`).
7. **SSH agent** on the Terraform runner with the private key that matches `ssh_public_key`. Hermes bootstrap SSHes to the Proxmox host (`pct exec`); k3s kubeconfig fetch SSHes to `192.168.0.20`.
8. **Tailscale pre-auth key** at [login.tailscale.com/admin/settings/keys](https://login.tailscale.com/admin/settings/keys) (Hermes `tailscale up`).
9. Optional: GitHub PAT if Argo must clone private repos or you hit GitHub rate limits.

### What `terraform apply` does

| Layer | How |
|-------|-----|
| Hermes LXC 210 | Clone Debian template, network, TUN device on the host, packages, Tailscale (`--ssh`) |
| Cloud-init snippet | Upload `cloud-init/k3s-user-data.yaml.tftpl` to `local:snippets/` |
| k3s VM 220 | Clone template 9000, LAN `192.168.0.20/24`. **First boot** installs `qemu-guest-agent` + k3s (`tls-san` / `node-ip` = `.20`) |
| kubeconfig | SSH wait/retry, write `terraform/.kube/k3s.yaml` (gitignored) |
| Argo CD | Helm release `argocd` into namespace `argocd` (second apply) |
| Root Application | Points at `k8s/argocd/apps` in this repo (same as `k8s/argocd/root.yaml`) |

### Two applies for Argo

Set `bootstrap = true`; it gates the cloud-init snippet, the hermes provisioners, the kubeconfig fetch and Argo. The Helm provider needs a kubeconfig at **plan** time, so the first apply creates the VM, runs cloud-init, and fetches kubeconfig. The second apply sees `terraform/.kube/k3s.yaml` and installs Argo + the root Application.

```bash
cd terraform
terraform init
terraform apply    # VM + k3s + kubeconfig
terraform apply    # Helm Argo CD + root Application
```

The live cluster's Argo CD was installed from upstream `install.yaml`, not this Helm release. Keep `bootstrap = false` against the live guests: it would also overwrite hermes `authorized_keys` and re-run `tailscale up`.

After Argo is up:

```bash
export KUBECONFIG=terraform/.kube/k3s.yaml
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
kubectl -n argocd port-forward svc/argocd-server 8080:80
```

Apps that need secrets (TLS, Cloudflare tunnel, Tailscale auth keys, …) stay degraded until those secrets exist on the new cluster. `argocd_exclude_app_files` can keep specific apps off a fresh cluster.

## API token

On alt (as root):

```bash
pveum user add terraform@pam
pveum role add Terraform -privs "Datastore.Allocate Datastore.AllocateSpace Datastore.AllocateTemplate Datastore.Audit Mapping.Audit Mapping.Modify Mapping.Use Sys.Audit Sys.Console Sys.Modify VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.Cloudinit VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Migrate VM.Monitor VM.PowerMgmt"
pveum aclmod / -user terraform@pam -role Terraform
pveum user token add terraform@pam terraform --privsep=0
```

Copy `terraform.tfvars.example` to `terraform.tfvars` (gitignored). Never commit `terraform.tfvars` or `terraform/.kube/`.

## Hermes LXC (`alt`)

Unprivileged Debian 13 container, VMID 210, `192.168.0.22/24` on `vmbr0`, disk on datastore `ssd` (zfspool). DNS is Pi-hole in k3s (`192.168.0.20`) plus `1.1.1.1`. TUN is patched on **alt** (`lxc.cgroup2` + `/dev/net/tun`) so Tailscale can run; `tailscale up` uses `--ssh`.

Proxmox LXC cloud-init only covers hostname/user/network, so first-boot packages and Tailscale stay `pct`/SSH provisioners (not a guest `user_data` script).

## k3s VM

`proxmox_virtual_environment_vm.k3s` clones Ubuntu cloud-init template **VMID 9000** into VMID 220 (`k3s`), 8 cores / 16 GiB (balloon floor 16 GiB, so no ballooning) / 120G on datastore `ssd`, virtio on `vmbr0`. It used to be `k3s_alt` (staging next to the old pve host); a `moved` block renames it in state.

Clone and scsi0 stay on `ssd` (zfspool). Cloud-init ISO (`initialization.datastore_id`) must be `local-lvm`, because Proxmox cannot store that ISO on a zfspool. `initialization.hostname` is not valid on this resource in bpg/proxmox 0.113; hostname is set in the user_data snippet. bpg also rejects `user_account` together with `user_data_file_id`, so SSH user/key/password live in the snippet.

Create the Ubuntu cloud template as VMID 9000 **before** a from-scratch apply. Bake `qemu-guest-agent` into it (`apt install qemu-guest-agent` and enable the service) so apply does not hang waiting for the guest agent.

`lifecycle.ignore_changes` includes `initialization`, so cloud-init changes never replace the running VM, and user_data changes do not re-run cloud-init on a disk that has already booted. `terraform apply -replace='proxmox_virtual_environment_vm.k3s'` reinstalls from scratch and **destroys the cluster**.

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

Host VFIO prep (GRUB `intel_iommu=on iommu=pt`, `vfio-pci` ids `10de:1f03,10de:10f9`, nouveau blacklist) is **not** managed by Terraform. Do not enable this while k3s 16 GiB + hermes are competing for the 32 GiB host unless you have confirmed headroom. The Terraform role needs `Mapping.Audit Mapping.Modify Mapping.Use` for the PCI mappings.
