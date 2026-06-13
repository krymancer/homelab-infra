resource "proxmox_virtual_environment_container" "dev" {
  node_name = "pve"
  vm_id     = var.dev_lxc.vmid

  description = "Dev box: claude code, codex, repo clones. Tailscale-attached."

  cpu {
    cores = var.dev_lxc.cores
  }

  memory {
    dedicated = var.dev_lxc.memory
  }

  disk {
    datastore_id = var.dev_lxc.storage
    size         = tonumber(replace(var.dev_lxc.disk, "G", ""))
  }

  network_interface {
    name   = "veth0"
    bridge = "vmbr0"
  }

  initialization {
    hostname = var.dev_lxc.name

    dns {
      servers = ["1.1.1.1", "8.8.8.8"]
    }

    ip_config {
      ipv4 {
        address = var.dev_lxc.ip
        gateway = var.dev_lxc.gateway
      }
    }

    user_account {
      password = var.ci_password
      keys     = [var.ssh_public_key]
    }
  }

  operating_system {
    template_file_id = var.dev_lxc.template
    type             = "archlinux"
  }

  features {
    nesting = true
  }

  unprivileged  = true
  start_on_boot = true
  started       = true
}

resource "null_resource" "dev_tun_config" {
  depends_on = [proxmox_virtual_environment_container.dev]

  triggers = {
    container_id = proxmox_virtual_environment_container.dev.id
  }

  connection {
    type    = "ssh"
    host    = regex("^https?://([^:/]+)", var.proxmox_api_url)[0]
    user    = "root"
    agent   = true
    timeout = "1m"
  }

  provisioner "remote-exec" {
    inline = [
      "set -e",
      "CFG=/etc/pve/lxc/${var.dev_lxc.vmid}.conf",
      "if ! grep -q 'lxc.mount.entry: /dev/net/tun' $CFG; then",
      "  echo 'lxc.cgroup2.devices.allow: c 10:200 rwm' >> $CFG",
      "  echo 'lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file' >> $CFG",
      "  pct reboot ${var.dev_lxc.vmid}",
      "  sleep 5",
      "fi",
    ]
  }
}

resource "null_resource" "dev_bootstrap" {
  depends_on = [null_resource.dev_tun_config]

  triggers = {
    container_id = proxmox_virtual_environment_container.dev.id
  }

  connection {
    type    = "ssh"
    host    = regex("^https?://([^:/]+)", var.proxmox_api_url)[0]
    user    = "root"
    agent   = true
    timeout = "3m"
  }

  provisioner "remote-exec" {
    inline = [
      "set -e",
      "VMID=${var.dev_lxc.vmid}",
      "until pct exec $VMID -- ping -c1 archlinux.org >/dev/null 2>&1; do sleep 2; done",
      "pct exec $VMID -- pacman-key --init",
      "pct exec $VMID -- pacman-key --populate",
      "pct exec $VMID -- pacman -Sy --noconfirm archlinux-keyring",
      "pct exec $VMID -- pacman -Syu --noconfirm",
      "pct exec $VMID -- pacman -S --noconfirm --needed openssh sudo curl git base-devel python python-pip tmux vim jq unzip nodejs npm tailscale fish mosh",
      "pct exec $VMID -- systemctl enable --now sshd tailscaled",
      "pct exec $VMID -- bash -c 'id ${var.ci_user} >/dev/null 2>&1 || useradd -m -s /usr/bin/fish -G wheel ${var.ci_user}'",
      "pct exec $VMID -- bash -c 'echo \"${var.ci_user} ALL=(ALL) NOPASSWD:ALL\" > /etc/sudoers.d/${var.ci_user}'",
      "pct exec $VMID -- install -d -m 0700 -o ${var.ci_user} -g ${var.ci_user} /home/${var.ci_user}/.ssh",
      "pct exec $VMID -- bash -c 'echo \"${var.ssh_public_key}\" > /home/${var.ci_user}/.ssh/authorized_keys'",
      "pct exec $VMID -- chown ${var.ci_user}:${var.ci_user} /home/${var.ci_user}/.ssh/authorized_keys",
      "pct exec $VMID -- chmod 600 /home/${var.ci_user}/.ssh/authorized_keys",
      "pct exec $VMID -- sudo -u ${var.ci_user} mkdir -p /home/${var.ci_user}/repos",
    ]
  }
}

resource "null_resource" "dev_provision" {
  depends_on = [null_resource.dev_bootstrap]

  triggers = {
    container_id = proxmox_virtual_environment_container.dev.id
  }

  connection {
    type    = "ssh"
    host    = split("/", var.dev_lxc.ip)[0]
    user    = "root"
    agent   = true
    timeout = "3m"
  }

  provisioner "remote-exec" {
    inline = [
      "set -e",
      "tailscale up --authkey=${var.tailscale_auth_key} --hostname=${var.dev_lxc.name} --ssh",
      "npm install -g @anthropic-ai/claude-code",
      "npm install -g @openai/codex",
    ]
  }
}
