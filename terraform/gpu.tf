# RTX 2060 passthrough scaffold on alt.
#
# Host facts (verified on the live machine; not managed here):
#   GPU   0000:03:00.0  [10de:1f03]  NVIDIA TU106 GeForce RTX 2060 12GB
#   Audio 0000:03:00.1  [10de:10f9]
#   IOMMU group 28 is clean (those two functions only) — no ACS override.
#   Host firmware is legacy BIOS; the guest still uses q35 + OVMF.
#
# Terraform models the VM PCI mapping only. GRUB (`intel_iommu=on iommu=pt`),
# vfio-pci ids, and the nouveau blacklist stay on the host. See README.md.
#
# Proxmox all-functions form for GPU + HDMI audio is hostpci0: 0000:03:00
# (pcie=1,rombar=1). bpg/proxmox documents hostpci.id as incompatible with
# api_token (needs root username/password), so we create Datacenter PCI
# mappings and attach them via hostpci.mapping for terraform@pam!terraform.

resource "proxmox_virtual_environment_hardware_mapping_pci" "rtx2060" {
  provider = proxmox.alt
  count    = var.enable_gpu_vm ? 1 : 0

  name    = "rtx2060"
  comment = "NVIDIA RTX 2060 12GB on alt (IOMMU group 28, 0000:03:00.0)"

  map = [
    {
      comment     = "TU106 GeForce RTX 2060 12GB"
      id          = "10de:1f03"
      iommu_group = 28
      node        = var.alt_node_name
      path        = "0000:03:00.0"
    },
  ]

  lifecycle {
    precondition {
      condition     = local.alt_token_configured
      error_message = "enable_gpu_vm requires proxmox_alt_api_token_id and proxmox_alt_api_token_secret. Create terraform@pam!terraform on alt — do not reuse the pve token."
    }
  }
}

resource "proxmox_virtual_environment_hardware_mapping_pci" "rtx2060_audio" {
  provider = proxmox.alt
  count    = var.enable_gpu_vm ? 1 : 0

  name    = "rtx2060-audio"
  comment = "NVIDIA RTX 2060 HD audio on alt (IOMMU group 28, 0000:03:00.1)"

  map = [
    {
      comment     = "TU106 HD Audio Controller"
      id          = "10de:10f9"
      iommu_group = 28
      node        = var.alt_node_name
      path        = "0000:03:00.1"
    },
  ]
}

resource "proxmox_virtual_environment_vm" "gpu" {
  provider = proxmox.alt
  count    = var.enable_gpu_vm ? 1 : 0

  name        = var.gpu_vm.name
  node_name   = var.alt_node_name
  vm_id       = var.gpu_vm.vmid
  description = "GPU passthrough scaffold (RTX 2060). Keep stopped while alt has 8 GiB RAM."
  tags        = ["alt", "gpu", "terraform"]

  # Must stay off on 8 GiB host RAM. Flip gpu_vm_started only after the 32 GiB upgrade.
  started = var.gpu_vm_started
  on_boot = false

  # Guest firmware: q35 + OVMF is the NVIDIA passthrough combination that works
  # even when the Proxmox host itself boots legacy BIOS.
  bios            = "ovmf"
  machine         = "q35"
  scsi_hardware   = "virtio-scsi-single"
  tablet_device   = false
  stop_on_destroy = true

  efi_disk {
    datastore_id = var.gpu_vm.storage
    type         = "4m"
    file_format  = "raw"
  }

  cpu {
    cores   = var.gpu_vm.cores
    sockets = 1
    type    = "host"
  }

  memory {
    dedicated = var.gpu_vm.memory
  }

  disk {
    interface    = "scsi0"
    size         = tonumber(replace(var.gpu_vm.disk, "G", ""))
    datastore_id = var.gpu_vm.storage
    file_format  = "raw"
    iothread     = true
  }

  # q35 only exposes ide0/ide2. Empty tray so an installer ISO can be attached later.
  cdrom {
    file_id   = "none"
    interface = "ide2"
  }

  network_device {
    model  = "virtio"
    bridge = "vmbr0"
  }

  # Full function 0000:03:00 (GPU + audio), token-safe via mappings.
  # rombar=true is the usual starting point for consumer NVIDIA; if the guest
  # Code 43s, try a dumped vBIOS (rom_file under /usr/share/kvm/) or rombar = false.
  hostpci {
    device  = "hostpci0"
    mapping = proxmox_virtual_environment_hardware_mapping_pci.rtx2060[0].name
    pcie    = true
    rombar  = true
  }

  hostpci {
    device  = "hostpci1"
    mapping = proxmox_virtual_environment_hardware_mapping_pci.rtx2060_audio[0].name
    pcie    = true
    rombar  = true
  }

  operating_system {
    type = "l26"
  }

  vga {
    type = "std"
  }

  lifecycle {
    ignore_changes = [
      cdrom,
      network_device,
    ]
  }
}
