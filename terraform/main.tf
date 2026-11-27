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
  k3s_ip              = split("/", var.k3s_vm.ip)[0]
  k3s_kubeconfig_path = "${path.module}/.kube/k3s.yaml"
  # Plan-time check: the fetch provisioner writes this file at the end of the
  # apply that boots k3s. Helm/root-app resources therefore appear on the next apply.
  k3s_kubeconfig_ready = fileexists(local.k3s_kubeconfig_path)
  k3s_bootstrap_argocd = var.bootstrap && local.k3s_kubeconfig_ready

  argocd_directory_exclude = length(var.argocd_exclude_app_files) == 0 ? "" : "{${join(",", var.argocd_exclude_app_files)}}"
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

# Single standalone Proxmox host `alt` (192.168.0.11).
provider "proxmox" {
  endpoint  = var.proxmox_api_url
  api_token = "${var.proxmox_api_token_id}=${var.proxmox_api_token_secret}"
  insecure  = true # self-signed cert on Proxmox

  ssh {
    agent = true

    node {
      name    = var.proxmox_node
      address = regex("^https?://([^:/]+)", var.proxmox_api_url)[0]
    }
  }
}

# Only used for from-scratch Argo bootstrap (var.bootstrap). Dummy
# kubeconfig lets the provider configure before the first-boot fetch.
provider "helm" {
  kubernetes {
    config_path = local.k3s_kubeconfig_ready ? local.k3s_kubeconfig_path : "${path.module}/kubeconfig-dummy.yaml"
  }
}
