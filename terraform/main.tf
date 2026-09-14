terraform {
  required_version = ">= 1.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.78"
    }
  }
}

locals {
  # Reuse pve token vars when alt-specific ones are unset. Create a matching
  # terraform@pam!terraform token on alt, or set proxmox_alt_api_token_*.
  proxmox_alt_api_token_id     = var.proxmox_alt_api_token_id != "" ? var.proxmox_alt_api_token_id : var.proxmox_api_token_id
  proxmox_alt_api_token_secret = var.proxmox_alt_api_token_secret != "" ? var.proxmox_alt_api_token_secret : var.proxmox_api_token_secret
}

# Default provider: Dell G15 / hostname `pve` (192.168.0.10).
# Existing k3s resources stay on this instance; do not attach an explicit
# `provider` meta-argument to them or Terraform will treat that as a move.
provider "proxmox" {
  endpoint  = var.proxmox_api_url
  api_token = "${var.proxmox_api_token_id}=${var.proxmox_api_token_secret}"
  insecure  = true # self-signed cert on Proxmox

  ssh {
    agent = true
  }
}

# Standalone second host (not clustered with pve). Pass `provider = proxmox.alt`
# on alt guests. Token vars fall back to the pve token when unset.
provider "proxmox" {
  alias     = "alt"
  endpoint  = var.proxmox_alt_api_url
  api_token = "${local.proxmox_alt_api_token_id}=${local.proxmox_alt_api_token_secret}"
  insecure  = true

  ssh {
    agent = true

    node {
      name    = var.alt_node_name
      address = regex("^https?://([^:/]+)", var.proxmox_alt_api_url)[0]
    }
  }
}

# Production k3s on pve (VMID 200, 192.168.0.20). Leave this resource on the
# default provider — an explicit `provider` meta-argument would look like a move
# and could destroy the live cluster. Cutover later may move services to
# proxmox_virtual_environment_vm.k3s_alt and reassign .20.
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
