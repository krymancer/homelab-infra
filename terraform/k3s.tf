# k3s VM on alt (VMID 220, 192.168.0.20). Runs the whole cluster.
#
# First boot (cloud-init user_data snippet): qemu-guest-agent + k3s server.
# user_data runs only on first boot of a new disk. This resource ignores
# initialization changes after create so the existing VM is not replaced.
# Recreate only when you want cloud-init to run again (destroys the cluster):
#   terraform apply -replace='proxmox_virtual_environment_vm.k3s'
#
# Prerequisites on alt: Ubuntu cloud-init template VMID 9000 (bake
# qemu-guest-agent), and snippets enabled on datastore `local`.

# Was k3s_alt while it ran as staging next to the old pve VM 200.
moved {
  from = proxmox_virtual_environment_vm.k3s_alt
  to   = proxmox_virtual_environment_vm.k3s
}

# Only needed to create the VM; the live VM ignores initialization changes.
resource "proxmox_virtual_environment_file" "k3s_user_data" {
  count = var.bootstrap ? 1 : 0

  content_type = "snippets"
  datastore_id = var.k3s_snippet_datastore
  node_name    = var.proxmox_node
  overwrite    = true

  source_raw {
    file_name = "k3s-user-data.yaml"
    data = templatefile("${path.module}/cloud-init/k3s-user-data.yaml.tftpl", {
      hostname       = var.k3s_vm.name
      ci_user        = var.ci_user
      ci_password    = var.ci_password
      ssh_public_key = var.ssh_public_key
      node_ip        = local.k3s_ip
    })
  }
}

resource "proxmox_virtual_environment_vm" "k3s" {
  name        = var.k3s_vm.name
  node_name   = var.proxmox_node
  vm_id       = var.k3s_vm.vmid
  description = "k3s on alt (${local.k3s_ip}). k3s is installed by cloud-init on first boot."

  started = true
  on_boot = true

  clone {
    vm_id        = var.k3s_vm.template
    node_name    = var.proxmox_node
    full         = true
    datastore_id = var.k3s_vm.storage
  }

  agent {
    enabled = true
    timeout = "15m"
  }

  cpu {
    cores   = var.k3s_vm.cores
    sockets = 1
    type    = "host"
  }

  # dedicated is the
  # ceiling (qm memory); floating is the balloon floor (qm balloon).
  # Unset floating defaults to 0 and would disable ballooning on the next apply.
  memory {
    dedicated = var.k3s_vm.memory
    floating  = var.k3s_vm.balloon
  }

  disk {
    interface    = "scsi0"
    size         = tonumber(replace(var.k3s_vm.disk, "G", ""))
    datastore_id = var.k3s_vm.storage
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
    user_data_file_id = one(proxmox_virtual_environment_file.k3s_user_data[*].id)

    dns {
      servers = ["192.168.0.20", "1.1.1.1"]
    }

    ip_config {
      ipv4 {
        address = var.k3s_vm.ip
        gateway = var.k3s_vm.gateway
      }
    }
  }

  lifecycle {
    ignore_changes = [
      network_device,
      # Do not replace the running VM when user_data or the cloud-init ISO
      # datastore changes. New creates still receive this block.
      initialization,
    ]
  }
}

# From-scratch only: wait for k3s then write a LAN kubeconfig for the Helm
# provider (next apply).
resource "terraform_data" "k3s_kubeconfig" {
  count = var.bootstrap ? 1 : 0

  depends_on = [proxmox_virtual_environment_vm.k3s]

  triggers_replace = [
    proxmox_virtual_environment_vm.k3s.id,
  ]

  connection {
    type    = "ssh"
    host    = local.k3s_ip
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
    command = "bash '${path.module}/scripts/fetch-kubeconfig.sh' '${var.ci_user}' '${local.k3s_ip}' '${local.k3s_kubeconfig_path}'"
  }
}
