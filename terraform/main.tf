terraform {
  required_version = ">= 1.4"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.78"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

locals {
  # Reuse pve token vars when alt-specific ones are unset. Create a matching
  # terraform@pam!terraform token on alt, or set proxmox_alt_api_token_*.
  proxmox_alt_api_token_id     = var.proxmox_alt_api_token_id != "" ? var.proxmox_alt_api_token_id : var.proxmox_api_token_id
  proxmox_alt_api_token_secret = var.proxmox_alt_api_token_secret != "" ? var.proxmox_alt_api_token_secret : var.proxmox_api_token_secret

  k3s_alt_ip              = split("/", var.k3s_alt_vm.ip)[0]
  k3s_alt_kubeconfig_path = "${path.module}/.kube/k3s-alt.yaml"
  # Plan-time check: the fetch provisioner writes this file at the end of the
  # apply that boots k3s. Helm/root-app resources therefore appear on the next apply.
  k3s_alt_kubeconfig_ready = fileexists(local.k3s_alt_kubeconfig_path)
  k3s_alt_bootstrap_argocd = var.k3s_alt_started && var.k3s_alt_bootstrap_argocd && local.k3s_alt_kubeconfig_ready

  argocd_exclude_files = var.argocd_sync_cutover_apps ? var.argocd_extra_exclude_app_files : compact(concat(
    ["pihole.yaml", "cloudflared.yaml"],
    var.argocd_extra_exclude_app_files,
  ))
  argocd_directory_exclude = length(local.argocd_exclude_files) == 0 ? "" : "{${join(",", local.argocd_exclude_files)}}"
  argocd_has_git_token     = nonsensitive(var.argocd_git_token) != ""

  argocd_helm_values = {
    configs = {
      params = {
        "server.insecure" = true
      }
    }
  }

  argocd_root_application = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "root"
      namespace = "argocd"
    }
    spec = {
      project = "default"
      source = merge(
        {
          repoURL        = var.argocd_repo_url
          targetRevision = var.argocd_target_revision
          path           = "k8s/argocd/apps"
        },
        local.argocd_directory_exclude == "" ? {} : {
          directory = {
            exclude = local.argocd_directory_exclude
            recurse = false
          }
        },
      )
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "argocd"
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
      }
    }
  }
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

# Staging k3s only. Production Argo on pve VM 200 is not managed by this root.
# Dummy kubeconfig lets the provider configure before the first-boot fetch.
provider "helm" {
  kubernetes {
    config_path = local.k3s_alt_kubeconfig_ready ? local.k3s_alt_kubeconfig_path : "${path.module}/kubeconfig-dummy.yaml"
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
