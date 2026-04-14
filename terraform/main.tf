terraform {
  required_version = ">= 1.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.78"
    }
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_api_url
  api_token = "${var.proxmox_api_token_id}=${var.proxmox_api_token_secret}"
  insecure  = true # self-signed cert on Proxmox

  ssh {
    agent = true
  }
}

resource "proxmox_virtual_environment_vm" "k3s" {
  name      = var.k3s_vm.name
  node_name = "pve"
  vm_id     = var.k3s_vm.vmid

  clone {
    vm_id = 9000
    full  = true
  }

  agent {
    enabled = true
  }

  cpu {
    cores   = var.k3s_vm.cores
    sockets = 1
    type    = "host"
  }

  memory {
    dedicated = var.k3s_vm.memory
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
    ip_config {
      ipv4 {
        address = var.k3s_vm.ip
        gateway = var.k3s_vm.gateway
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
