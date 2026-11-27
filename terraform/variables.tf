variable "proxmox_api_url" {
  description = "Proxmox API URL (alt)"
  type        = string
  default     = "https://192.168.0.11:8006"
}

variable "proxmox_api_token_id" {
  description = "Proxmox API token ID (e.g. terraform@pam!terraform)"
  type        = string
  sensitive   = true
}

variable "proxmox_api_token_secret" {
  description = "Proxmox API token secret"
  type        = string
  sensitive   = true
}

variable "proxmox_node" {
  description = "Proxmox node name (hostname, not FQDN)"
  type        = string
  default     = "alt"
}

variable "k3s_vm" {
  description = "k3s VM on alt. 192.168.0.20 is also the Pi-hole / ingress LoadBalancer IP."
  type = object({
    vmid     = number
    name     = string
    cores    = number
    memory   = number
    balloon  = optional(number, 16384)
    disk     = string
    storage  = string
    ip       = string
    gateway  = string
    template = number
  })
  default = {
    vmid     = 220
    name     = "k3s"
    cores    = 8
    memory   = 16384
    balloon  = 16384
    disk     = "120G"
    storage  = "ssd"
    ip       = "192.168.0.20/24"
    gateway  = "192.168.0.1"
    template = 9000
  }
}

variable "k3s_snippet_datastore" {
  description = "Datastore on alt that allows Snippets content (usually local). Enable with: pvesm set local --content backup,iso,vztmpl,snippets"
  type        = string
  default     = "local"
}

variable "bootstrap" {
  description = "From-scratch only: upload the k3s cloud-init snippet, run the hermes provisioners (TUN, packages, tailscale up), fetch the k3s kubeconfig, then (second apply) install Argo CD via Helm and apply the root Application. Keep false against the live guests."
  type        = bool
  default     = false
}

variable "argocd_chart_version" {
  description = "argo-cd Helm chart version from https://argoproj.github.io/argo-helm"
  type        = string
  default     = "10.17.1"
}

variable "argocd_repo_url" {
  description = "Git repo the root Application syncs"
  type        = string
  default     = "https://github.com/krymancer/infra.git"
}

variable "argocd_target_revision" {
  description = "Git revision for the root Application (usually main)"
  type        = string
  default     = "main"
}

variable "argocd_repo_credential_url" {
  description = "Prefix for Argo repo credential templates when argocd_git_token is set. Covers this repo and other https://github.com/krymancer/* apps."
  type        = string
  default     = "https://github.com/krymancer"
}

variable "argocd_git_token" {
  description = "Optional GitHub PAT for Argo to clone private repos / higher rate limits. Empty skips credentialTemplates."
  type        = string
  sensitive   = true
  default     = ""
}

variable "argocd_exclude_app_files" {
  description = "Filenames under k8s/argocd/apps to exclude from the bootstrapped root Application (e.g. [\"tailscale.yaml\"])."
  type        = list(string)
  default     = []
}

variable "enable_gpu_vm" {
  description = "Create the RTX 2060 passthrough VM on alt. Leave false until RAM headroom is confirmed."
  type        = bool
  default     = false
}

variable "gpu_vm_started" {
  description = "Whether Terraform should start the GPU VM. Must stay false unless enable_gpu_vm is true and you intend to boot it."
  type        = bool
  default     = false
}

variable "gpu_vm" {
  description = "Placeholder GPU passthrough VM on alt (count=0 unless enable_gpu_vm)."
  type = object({
    vmid    = number
    name    = string
    cores   = number
    memory  = number
    disk    = string
    storage = string
  })
  default = {
    vmid    = 300
    name    = "gpu"
    cores   = 4
    memory  = 8192
    disk    = "64G"
    storage = "ssd"
  }
}

variable "ssh_public_key" {
  description = "SSH public key for VM access"
  type        = string
}

variable "ci_user" {
  description = "Cloud-init default user"
  type        = string
  default     = "junho"
}

variable "ci_password" {
  description = "Cloud-init default user password"
  type        = string
  sensitive   = true
}

variable "tailscale_auth_key" {
  description = "Tailscale pre-auth key (tskey-auth-...). Create at login.tailscale.com/admin/settings/keys."
  type        = string
  sensitive   = true
}

variable "hermes_lxc" {
  description = "Hermes Debian LXC on alt"
  type = object({
    vmid     = number
    name     = string
    cores    = number
    memory   = number
    disk     = string
    storage  = string
    ip       = string
    gateway  = string
    template = string
  })
  default = {
    vmid    = 210
    name    = "hermes"
    cores   = 2
    memory  = 4096
    disk    = "16G"
    storage = "ssd"
    ip      = "192.168.0.22/24"
    gateway = "192.168.0.1"
    # Confirm on alt: `pveam list local`. Download if missing:
    #   pveam update && pveam download local debian-13-standard
    template = "local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst"
  }
}
