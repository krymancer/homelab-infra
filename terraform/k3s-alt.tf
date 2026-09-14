# Staging k3s VM on alt (prep only; started = false).
#
# Production remains proxmox_virtual_environment_vm.k3s on pve (VMID 200,
# 192.168.0.20) until cutover. TF resource stays k3s_alt so it does not collide
# with pve's k3s; Proxmox VM name is `k3s`.
# A later cutover will move cluster services here and may reassign 192.168.0.20.
#
# Prerequisite on alt before apply: Ubuntu cloud-init template VMID 9000
# (include qemu-guest-agent so apply does not hang waiting for the agent).

resource "proxmox_virtual_environment_vm" "k3s_alt" {
  provider = proxmox.alt

  name        = var.k3s_alt_vm.name
  node_name   = var.alt_node_name
  vm_id       = var.k3s_alt_vm.vmid
  description = "Staging k3s on alt. Stopped until cutover; production remains VM 200 on pve (192.168.0.20)."

  # Prep only. Flip k3s_alt_started after template 9000 exists and you are ready to boot.
  started = var.k3s_alt_started
  on_boot = false

  clone {
    vm_id        = var.k3s_alt_vm.template
    node_name    = var.alt_node_name
    full         = true
    datastore_id = var.k3s_alt_vm.storage
  }

  agent {
    enabled = true
  }

  cpu {
    cores   = var.k3s_alt_vm.cores
    sockets = 1
    type    = "host"
  }

  memory {
    dedicated = var.k3s_alt_vm.memory
  }

  disk {
    interface    = "scsi0"
    size         = tonumber(replace(var.k3s_alt_vm.disk, "G", ""))
    datastore_id = var.k3s_alt_vm.storage
  }

  network_device {
    model  = "virtio"
    bridge = "vmbr0"
  }

  initialization {
    # Cloud-init ISO cannot live on zfspool (`ssd`). Clone/scsi0 stay on ssd.
    # bpg/proxmox 0.113 has no initialization.hostname on this resource.
    datastore_id = "local-lvm"

    dns {
      servers = ["192.168.0.20", "1.1.1.1"]
    }

    ip_config {
      ipv4 {
        address = var.k3s_alt_vm.ip
        gateway = var.k3s_alt_vm.gateway
      }
    }

    user_account {
      username = var.ci_user
      password = var.ci_password
      keys     = [var.ssh_public_key]
    }
  }

  lifecycle {
    ignore_changes = [
      network_device,
    ]
  }
}
