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
