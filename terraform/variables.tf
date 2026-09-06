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
  description = "API token ID on alt (e.g. terraform@pam!terraform). Required to manage alt resources."
  type        = string
  sensitive   = true
  default     = ""
}

variable "proxmox_alt_api_token_secret" {
  description = "API token secret for alt. Create on alt; do not reuse the pve token."
  type        = string
  sensitive   = true
  default     = ""
}

variable "k3s_node_name" {
  description = "Proxmox node that owns the k3s VM. Keep pve until alt has 32 GiB RAM."
  type        = string
  default     = "pve"
}

variable "dev_node_name" {
  description = "Proxmox node that owns the dev LXC. Keep pve until alt has 32 GiB RAM."
  type        = string
  default     = "pve"
}

variable "alt_node_name" {
  description = "Proxmox node name of the second host (hostname, not FQDN)"
  type        = string
  default     = "alt"
}

variable "k3s_vm" {
  description = "K3s VM configuration"
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

variable "dev_lxc" {
  description = "Dev LXC container configuration"
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
    vmid     = 201
    name     = "dev"
    cores    = 8
    memory   = 8192
    disk     = "90G"
    storage  = "local-lvm"
    ip       = "192.168.0.21/24"
    gateway  = "192.168.0.1"
    template = "local:vztmpl/archlinux-base_20260420-1_amd64.tar.zst"
  }
}

variable "enable_gpu_vm" {
  description = "Create the RTX 2060 passthrough VM on alt. Leave false while alt has 8 GiB RAM."
  type        = bool
  default     = false
}

variable "gpu_vm_started" {
  description = "Whether Terraform should start the GPU VM. Must stay false on 8 GiB host RAM."
  type        = bool
  default     = false
}

variable "gpu_vm" {
  description = "Placeholder GPU passthrough VM on alt. Do not start until alt has 32 GiB RAM."
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
    vmid    = 300
    name    = "gpu"
    cores   = 4
    memory  = 8192
    disk    = "64G"
    storage = "local-lvm"
    ip      = "192.168.0.30/24"
    gateway = "192.168.0.1"
  }
}
