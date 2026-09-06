terraform {
  required_version = ">= 1.2"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.78"
    }
  }
}

locals {
  alt_token_configured = (
    var.proxmox_alt_api_token_id != "" &&
    var.proxmox_alt_api_token_secret != ""
  )
}

# Default provider: Dell G15 / hostname `pve` (192.168.0.10).
# Existing k3s + dev resources stay on this instance; do not attach an explicit
# `provider` meta-argument to them or Terraform will treat that as a move.
provider "proxmox" {
  endpoint  = var.proxmox_api_url
  api_token = "${var.proxmox_api_token_id}=${var.proxmox_api_token_secret}"
  insecure  = true # self-signed cert on Proxmox

  ssh {
    agent = true
  }
}

# Standalone second host (not clustered with pve). Needs its own API token.
# When alt tokens are unset, this alias points at pve so existing pve-only
# plans keep working. Set the alt token vars before managing GPU resources.
provider "proxmox" {
  alias     = "alt"
  endpoint  = local.alt_token_configured ? var.proxmox_alt_api_url : var.proxmox_api_url
  api_token = local.alt_token_configured ? "${var.proxmox_alt_api_token_id}=${var.proxmox_alt_api_token_secret}" : "${var.proxmox_api_token_id}=${var.proxmox_api_token_secret}"
  insecure  = true

  ssh {
    agent = true

    node {
      name    = var.alt_node_name
      address = regex("^https?://([^:/]+)", var.proxmox_alt_api_url)[0]
    }
  }
}

resource "proxmox_virtual_environment_vm" "k3s" {
  name      = var.k3s_vm.name
  node_name = var.k3s_node_name
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
