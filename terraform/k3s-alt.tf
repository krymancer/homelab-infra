# Staging k3s VM on alt.
#
# Production remains proxmox_virtual_environment_vm.k3s on pve (VMID 200,
# 192.168.0.20) until cutover. TF resource stays k3s_alt so it does not collide
# with pve's k3s; Proxmox VM name is `k3s`.
# A later cutover will move cluster services here and may reassign 192.168.0.20.
#
# First boot (cloud-init user_data snippet): qemu-guest-agent + k3s server.
# user_data runs only on first boot of a new disk. This resource ignores
# initialization changes after create so an already-cloned VM 220 is not
# replaced. Recreate when you want cloud-init to run:
#   terraform apply -replace='proxmox_virtual_environment_vm.k3s_alt'
#
# Prerequisites on alt: Ubuntu cloud-init template VMID 9000 (bake
# qemu-guest-agent), and snippets enabled on datastore `local`.

resource "proxmox_virtual_environment_file" "k3s_alt_user_data" {
  provider = proxmox.alt

  content_type = "snippets"
  datastore_id = var.k3s_alt_snippet_datastore
  node_name    = var.alt_node_name
  overwrite    = true

  source_raw {
    file_name = "k3s-alt-user-data.yaml"
    data = templatefile("${path.module}/cloud-init/k3s-alt-user-data.yaml.tftpl", {
      hostname       = var.k3s_alt_vm.name
      ci_user        = var.ci_user
      ci_password    = var.ci_password
      ssh_public_key = var.ssh_public_key
      node_ip        = local.k3s_alt_ip
    })
  }
}

resource "proxmox_virtual_environment_vm" "k3s_alt" {
  provider = proxmox.alt

  name        = var.k3s_alt_vm.name
  node_name   = var.alt_node_name
  vm_id       = var.k3s_alt_vm.vmid
  description = "Staging k3s on alt (${local.k3s_alt_ip}). Production remains VM 200 on pve (192.168.0.20). k3s is installed by cloud-init on first boot."

  started = var.k3s_alt_started
  on_boot = var.k3s_alt_started

  clone {
    vm_id        = var.k3s_alt_vm.template
    node_name    = var.alt_node_name
    full         = true
    datastore_id = var.k3s_alt_vm.storage
  }

  agent {
    enabled = true
    timeout = "15m"
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
    # bpg/proxmox 0.113 has no initialization.hostname on this resource; hostname
    # is set in the user_data snippet. user_account conflicts with
    # user_data_file_id — SSH user/key/password live in the snippet.
    datastore_id      = "local-lvm"
    user_data_file_id = proxmox_virtual_environment_file.k3s_alt_user_data.id

    dns {
      servers = ["192.168.0.20", "1.1.1.1"]
    }

    ip_config {
      ipv4 {
        address = var.k3s_alt_vm.ip
        gateway = var.k3s_alt_vm.gateway
      }
    }
  }

  lifecycle {
    ignore_changes = [
      network_device,
      # Do not replace an already-cloned staging VM when user_data or the
      # cloud-init ISO datastore is added. New creates still receive this block.
      initialization,
    ]
  }
}

# Wait for k3s then write a LAN kubeconfig for the Helm provider (next apply).
resource "terraform_data" "k3s_alt_kubeconfig" {
  count = var.k3s_alt_started ? 1 : 0

  depends_on = [proxmox_virtual_environment_vm.k3s_alt]

  triggers_replace = [
    proxmox_virtual_environment_vm.k3s_alt.id,
  ]

  connection {
    type    = "ssh"
    host    = local.k3s_alt_ip
    user    = var.ci_user
    agent   = true
    timeout = "20m"
  }

  provisioner "remote-exec" {
    inline = [
      "set -euo pipefail",
      "echo waiting for k3s API...",
      "i=0",
      "until sudo k3s kubectl get nodes >/dev/null 2>&1; do i=$((i+1)); if [ \"$i\" -gt 120 ]; then echo timed out waiting for k3s; exit 1; fi; sleep 5; done",
      "sudo k3s kubectl wait --for=condition=Ready nodes --all --timeout=300s",
    ]
  }

  provisioner "local-exec" {
    command = "bash '${path.module}/scripts/fetch-kubeconfig.sh' '${var.ci_user}' '${local.k3s_alt_ip}' '${local.k3s_alt_kubeconfig_path}'"
  }
}
