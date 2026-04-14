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
