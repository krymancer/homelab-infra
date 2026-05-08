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

output "dev_ip" {
  description = "LAN IP of dev LXC"
  value       = var.dev_lxc.ip
}

output "dev_ssh_lan" {
  description = "SSH command (LAN)"
  value       = "ssh ${var.ci_user}@${split("/", var.dev_lxc.ip)[0]}"
}

output "dev_ssh_tailscale" {
  description = "SSH via Tailscale MagicDNS (after first connect)"
  value       = "ssh ${var.ci_user}@${var.dev_lxc.name}"
}
