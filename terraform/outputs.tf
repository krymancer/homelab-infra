output "k3s_ip" {
  description = "IP address of the k3s VM"
  value       = var.k3s_vm.ip
}

output "k3s_vmid" {
  description = "VMID of the k3s VM"
  value       = proxmox_virtual_environment_vm.k3s.vm_id
}

output "k3s_ssh" {
  description = "SSH command to connect to k3s VM"
  value       = "ssh ${var.ci_user}@${split("/", var.k3s_vm.ip)[0]}"
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

output "k3s_alt_ip" {
  description = "Staging IP of k3s on alt (production k3s stays on 192.168.0.20 until cutover)"
  value       = var.k3s_alt_vm.ip
}

output "k3s_alt_vmid" {
  description = "VMID of the staging k3s VM on alt"
  value       = proxmox_virtual_environment_vm.k3s_alt.vm_id
}

output "k3s_alt_ssh" {
  description = "SSH command for staging k3s on alt (only useful after the VM is started)"
  value       = "ssh ${var.ci_user}@${split("/", var.k3s_alt_vm.ip)[0]}"
}

output "k3s_alt_started" {
  description = "Whether Terraform is configured to start staging k3s on alt"
  value       = var.k3s_alt_started
}

output "k3s_alt_kubeconfig" {
  description = "Path to the fetched staging kubeconfig (gitignored). Empty until the first-boot fetch runs."
  value       = local.k3s_alt_kubeconfig_ready ? local.k3s_alt_kubeconfig_path : null
}

output "k3s_alt_argocd_bootstrapped" {
  description = "Whether this plan includes Helm Argo CD + root Application (needs kubeconfig from a prior apply)"
  value       = local.k3s_alt_bootstrap_argocd
}

output "k3s_alt_argocd_exclude" {
  description = "App manifests excluded from the staging root Application"
  value       = local.argocd_exclude_files
}

output "k3s_alt_argocd_admin_secret" {
  description = "How to read the initial Argo CD admin password after bootstrap"
  value       = "kubectl --kubeconfig terraform/.kube/k3s-alt.yaml -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}

output "gpu_vm_enabled" {
  description = "Whether the alt GPU passthrough VM is managed by Terraform"
  value       = var.enable_gpu_vm
}

output "gpu_vm_id" {
  description = "VMID of the GPU passthrough VM (null while enable_gpu_vm is false)"
  value       = var.enable_gpu_vm ? proxmox_virtual_environment_vm.gpu[0].vm_id : null
}
