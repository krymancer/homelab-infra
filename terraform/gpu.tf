# Optional RTX 2060 passthrough scaffold on alt. Off by default (count = 0).
#
# Host facts (verified on the live machine; not managed here):
#   GPU   0000:03:00.0  [10de:1f03]  NVIDIA TU106 GeForce RTX 2060 12GB
#   Audio 0000:03:00.1  [10de:10f9]
#   IOMMU group 28 is clean (those two functions only).
#
# Terraform models PCI mappings + a stopped VM only. GRUB (intel_iommu=on
# iommu=pt), vfio-pci ids, and the nouveau blacklist stay on the host.
# bpg/proxmox hostpci.id is incompatible with API tokens, so mappings are used.
#
# Leave enable_gpu_vm = false until k3s-alt cutover RAM headroom is confirmed
# (k3s-alt 16G + hermes 2G on a 32G host).

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
  description = "GPU passthrough scaffold (RTX 2060). Keep stopped until RAM headroom is confirmed."

  started = var.gpu_vm_started
  on_boot = false

  bios          = "ovmf"
  machine       = "q35"
  scsi_hardware = "virtio-scsi-single"

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

  cdrom {
    file_id   = "none"
    interface = "ide2"
  }

  network_device {
    model  = "virtio"
    bridge = "vmbr0"
  }

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

  lifecycle {
    ignore_changes = [
      cdrom,
      network_device,
    ]
  }
}
