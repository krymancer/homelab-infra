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
    type             = "debian"
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
      "  pct restart ${var.dev_lxc.vmid}",
      "  sleep 5",
      "fi",
    ]
  }
}

resource "null_resource" "dev_provision" {
  depends_on = [null_resource.dev_tun_config]

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
      "until ping -c1 deb.debian.org >/dev/null 2>&1; do sleep 2; done",
      "export DEBIAN_FRONTEND=noninteractive",
      "apt-get update -y",
      "apt-get install -y curl git ca-certificates gnupg build-essential python3 python3-pip python3-venv tmux vim jq unzip sudo openssh-server",
      "systemctl enable --now ssh",
      "id ${var.ci_user} >/dev/null 2>&1 || useradd -m -s /bin/bash -G sudo ${var.ci_user}",
      "echo '${var.ci_user} ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/${var.ci_user}",
      "install -d -m 0700 -o ${var.ci_user} -g ${var.ci_user} /home/${var.ci_user}/.ssh",
      "echo '${var.ssh_public_key}' > /home/${var.ci_user}/.ssh/authorized_keys",
      "chown ${var.ci_user}:${var.ci_user} /home/${var.ci_user}/.ssh/authorized_keys",
      "chmod 600 /home/${var.ci_user}/.ssh/authorized_keys",
      "sudo -u ${var.ci_user} mkdir -p /home/${var.ci_user}/repos",
      "curl -fsSL https://tailscale.com/install.sh | sh",
      "tailscale up --authkey=${var.tailscale_auth_key} --hostname=${var.dev_lxc.name} --ssh",
      "curl -fsSL https://deb.nodesource.com/setup_22.x | bash -",
      "apt-get install -y nodejs",
      "npm install -g @anthropic-ai/claude-code",
      "npm install -g @openai/codex",
    ]
  }
}
