resource "proxmox_virtual_environment_container" "hermes" {
  provider = proxmox.alt

  node_name = var.alt_node_name
  vm_id     = var.hermes_lxc.vmid

  description = "Minimal Debian LXC on alt. Tailscale-attached."

  cpu {
    cores = var.hermes_lxc.cores
  }

  memory {
    dedicated = var.hermes_lxc.memory
  }

  disk {
    datastore_id = var.hermes_lxc.storage
    size         = tonumber(replace(var.hermes_lxc.disk, "G", ""))
  }

  network_interface {
    name   = "eth0"
    bridge = "vmbr0"
  }

  initialization {
    hostname = var.hermes_lxc.name

    dns {
      servers = ["192.168.0.20", "1.1.1.1"]
    }

    ip_config {
      ipv4 {
        address = var.hermes_lxc.ip
        gateway = var.hermes_lxc.gateway
      }
    }

    user_account {
      password = var.ci_password
      keys     = [var.ssh_public_key]
    }
  }

  operating_system {
    template_file_id = var.hermes_lxc.template
    # bpg/proxmox ostype for Debian is `debian` (Proxmox debianlinux equivalent).
    type = "debian"
  }

  features {
    nesting = true
  }

  unprivileged  = true
  start_on_boot = true
  started       = true
}

resource "null_resource" "hermes_tun_config" {
  depends_on = [proxmox_virtual_environment_container.hermes]

  triggers = {
    container_id = proxmox_virtual_environment_container.hermes.id
  }

  connection {
    type    = "ssh"
    host    = regex("^https?://([^:/]+)", var.proxmox_alt_api_url)[0]
    user    = "root"
    agent   = true
    timeout = "1m"
  }

  provisioner "remote-exec" {
    inline = [
      "set -e",
      "CFG=/etc/pve/lxc/${var.hermes_lxc.vmid}.conf",
      "if ! grep -q 'lxc.mount.entry: /dev/net/tun' $CFG; then",
      "  echo 'lxc.cgroup2.devices.allow: c 10:200 rwm' >> $CFG",
      "  echo 'lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file' >> $CFG",
      "  pct reboot ${var.hermes_lxc.vmid}",
      "  sleep 5",
      "fi",
    ]
  }
}

resource "null_resource" "hermes_bootstrap" {
  depends_on = [null_resource.hermes_tun_config]

  triggers = {
    container_id = proxmox_virtual_environment_container.hermes.id
  }

  connection {
    type    = "ssh"
    host    = regex("^https?://([^:/]+)", var.proxmox_alt_api_url)[0]
    user    = "root"
    agent   = true
    timeout = "10m"
  }

  provisioner "remote-exec" {
    inline = [
      "set -e",
      "VMID=${var.hermes_lxc.vmid}",
      "until pct exec $VMID -- ping -c1 1.1.1.1 >/dev/null 2>&1; do sleep 2; done",
      "pct exec $VMID -- env DEBIAN_FRONTEND=noninteractive apt-get update",
      "pct exec $VMID -- env DEBIAN_FRONTEND=noninteractive apt-get install -y openssh-server sudo curl git python3 python3-pip tmux vim jq unzip ca-certificates gnupg fish",
      "pct exec $VMID -- mkdir -p --mode=0755 /usr/share/keyrings",
      "pct exec $VMID -- bash -c 'curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.noarmor.gpg > /usr/share/keyrings/tailscale-archive-keyring.gpg'",
      "pct exec $VMID -- bash -c 'curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.tailscale-keyring.list > /etc/apt/sources.list.d/tailscale.list'",
      "pct exec $VMID -- env DEBIAN_FRONTEND=noninteractive apt-get update",
      "pct exec $VMID -- env DEBIAN_FRONTEND=noninteractive apt-get install -y tailscale",
      "pct exec $VMID -- systemctl enable --now ssh tailscaled",
      "pct exec $VMID -- bash -c 'id ${var.ci_user} >/dev/null 2>&1 || useradd -m -s /usr/bin/fish -G sudo ${var.ci_user}'",
      "pct exec $VMID -- bash -c 'echo \"${var.ci_user} ALL=(ALL) NOPASSWD:ALL\" > /etc/sudoers.d/${var.ci_user}'",
      "pct exec $VMID -- chmod 440 /etc/sudoers.d/${var.ci_user}",
      "pct exec $VMID -- install -d -m 0700 -o ${var.ci_user} -g ${var.ci_user} /home/${var.ci_user}/.ssh",
      "pct exec $VMID -- bash -c 'echo \"${var.ssh_public_key}\" > /home/${var.ci_user}/.ssh/authorized_keys'",
      "pct exec $VMID -- chown ${var.ci_user}:${var.ci_user} /home/${var.ci_user}/.ssh/authorized_keys",
      "pct exec $VMID -- chmod 600 /home/${var.ci_user}/.ssh/authorized_keys",
    ]
  }
}

resource "null_resource" "hermes_provision" {
  depends_on = [null_resource.hermes_bootstrap]

  triggers = {
    container_id = proxmox_virtual_environment_container.hermes.id
  }

  connection {
    type    = "ssh"
    host    = split("/", var.hermes_lxc.ip)[0]
    user    = "root"
    agent   = true
    timeout = "3m"
  }

  provisioner "remote-exec" {
    inline = [
      "set -e",
      "tailscale up --authkey=${var.tailscale_auth_key} --hostname=${var.hermes_lxc.name} --ssh",
    ]
  }
}
