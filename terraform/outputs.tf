output "k3s_ip" {
  description = "IP address of the k3s VM"
  value       = var.k3s_vm.ip
}

output "k3s_vmid" {
  description = "VMID of the k3s VM"
  value       = proxmox_virtual_environment_vm.k3s.vm_id
}

output "k3s_ssh" {
  description = "SSH command to connect to the k3s VM"
  value       = "ssh ${var.ci_user}@${local.k3s_ip}"
}

output "k3s_kubeconfig" {
  description = "Path to the fetched kubeconfig (gitignored). Null until a bootstrap apply fetched it."
  value       = local.k3s_kubeconfig_ready ? local.k3s_kubeconfig_path : null
}

output "argocd_bootstrapped" {
  description = "Whether this plan includes Helm Argo CD + root Application"
  value       = local.k3s_bootstrap_argocd
}

output "hermes_ip" {
  description = "LAN IP of hermes LXC on alt"
  value       = var.hermes_lxc.ip
}

output "hermes_vmid" {
  description = "VMID of hermes LXC"
  value       = proxmox_virtual_environment_container.hermes.vm_id
}

output "hermes_ssh_lan" {
  description = "SSH command (LAN)"
  value       = "ssh ${var.ci_user}@${split("/", var.hermes_lxc.ip)[0]}"
}

output "hermes_ssh_tailscale" {
  description = "SSH via Tailscale MagicDNS (after first connect)"
  value       = "ssh ${var.ci_user}@${var.hermes_lxc.name}"
}

output "gpu_vm_enabled" {
  description = "Whether the alt GPU passthrough VM is managed by Terraform"
  value       = var.enable_gpu_vm
}

output "gpu_vm_id" {
  description = "VMID of the GPU passthrough VM (null while enable_gpu_vm is false)"
  value       = var.enable_gpu_vm ? proxmox_virtual_environment_vm.gpu[0].vm_id : null
}
