variable "proxmox_api_url" {
  description = "Proxmox API URL"
  type        = string
  default     = "https://192.168.0.10:8006"
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

variable "proxmox_alt_api_url" {
  description = "Proxmox API URL for the standalone alt host (not clustered with pve)"
  type        = string
  default     = "https://192.168.0.11:8006"
}

variable "proxmox_alt_api_token_id" {
  description = "API token ID on alt (e.g. terraform@pam!terraform). Empty reuses proxmox_api_token_id."
  type        = string
  sensitive   = true
  default     = ""
}

variable "proxmox_alt_api_token_secret" {
  description = "API token secret for alt. Empty reuses proxmox_api_token_secret. Prefer a token created on alt."
  type        = string
  sensitive   = true
  default     = ""
}

variable "alt_node_name" {
  description = "Proxmox node name of the second host (hostname, not FQDN)"
  type        = string
  default     = "alt"
}

variable "k3s_vm" {
  description = "Production k3s VM on pve. Leave as-is until cutover; .20 stays on this guest."
  type = object({
    vmid    = number
    name    = string
    cores   = number
    memory  = number
    disk    = string
    storage = string
    ip      = string
    gateway = string
  })
  default = {
    vmid    = 200
    name    = "k3s"
    cores   = 4
    memory  = 8192
    disk    = "40G"
    storage = "local-lvm"
    ip      = "192.168.0.20/24"
    gateway = "192.168.0.1"
  }
}

variable "k3s_alt_vm" {
  description = "Staging k3s VM on alt. Cutover later may move services from pve VM 200 and reassign 192.168.0.20."
  type = object({
    vmid     = number
    name     = string
    cores    = number
    memory   = number
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
    disk     = "120G"
    storage  = "ssd"
    ip       = "192.168.0.23/24"
    gateway  = "192.168.0.1"
    template = 9000
  }
}

variable "k3s_alt_started" {
  description = "Start the staging k3s VM on alt. Keep false until Ubuntu cloud template 9000 exists on alt and you are ready to boot. Cloud-init installs k3s on first boot."
  type        = bool
  default     = false
}

variable "k3s_alt_snippet_datastore" {
  description = "Datastore on alt that allows Snippets content (usually local). Enable with: pvesm set local --content backup,iso,vztmpl,snippets"
  type        = string
  default     = "local"
}

variable "k3s_alt_bootstrap_argocd" {
  description = "After k3s is up, install Argo CD via Helm and apply the root Application. Requires k3s_alt_started=true and a second apply once kubeconfig has been fetched to terraform/.kube/k3s-alt.yaml."
  type        = bool
  default     = true
}

variable "argocd_chart_version" {
  description = "argo-cd Helm chart version from https://argoproj.github.io/argo-helm"
  type        = string
  default     = "10.8.3"
}

variable "argocd_repo_url" {
  description = "Git repo the staging root Application syncs"
  type        = string
  default     = "https://github.com/krymancer/homelab-infra.git"
}

variable "argocd_target_revision" {
  description = "Git revision for the staging root Application (usually main)"
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

variable "argocd_sync_cutover_apps" {
  description = "When false (default), staging Argo skips pihole.yaml (LoadBalancer 192.168.0.20) and cloudflared.yaml (shared tunnel). Set true only at cutover when this cluster should own those apps."
  type        = bool
  default     = false
}

variable "argocd_extra_exclude_app_files" {
  description = "Additional filenames under k8s/argocd/apps to exclude from the staging root Application (e.g. [\"tailscale.yaml\"])."
  type        = list(string)
  default     = []
}

variable "enable_gpu_vm" {
  description = "Create the RTX 2060 passthrough VM on alt. Leave false until staging k3s RAM headroom is confirmed."
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
    memory  = 2048
    disk    = "16G"
    storage = "ssd"
    ip      = "192.168.0.22/24"
    gateway = "192.168.0.1"
    # Confirm on alt: `pveam list local`. Download if missing:
    #   pveam update && pveam download local debian-13-standard
    template = "local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst"
  }
}
