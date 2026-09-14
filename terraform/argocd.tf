# Argo CD on staging k3s (alt VM 220). Helm provider talks to the kubeconfig
# fetched after first boot. The Helm provider configures at plan time, so a
# brand-new cluster needs two applies once k3s_alt_started is true:
#   1. VM + cloud-init k3s + kubeconfig file
#   2. helm_release + root Application
#
# Production Argo on pve VM 200 is not managed here.

resource "helm_release" "argocd" {
  count = local.k3s_alt_bootstrap_argocd ? 1 : 0

  depends_on = [terraform_data.k3s_alt_kubeconfig]

  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version
  namespace        = "argocd"
  create_namespace = true
  wait             = true
  timeout          = 1200
  max_history      = 3
  atomic           = false

  values = [yamlencode(local.argocd_helm_values)]

  dynamic "set" {
    for_each = local.argocd_has_git_token ? toset(["homelab"]) : toset([])
    content {
      name  = "configs.credentialTemplates.homelab.url"
      value = var.argocd_repo_credential_url
    }
  }

  dynamic "set" {
    for_each = local.argocd_has_git_token ? toset(["homelab"]) : toset([])
    content {
      name  = "configs.credentialTemplates.homelab.username"
      value = "git"
    }
  }

  dynamic "set_sensitive" {
    for_each = local.argocd_has_git_token ? toset(["homelab"]) : toset([])
    content {
      name  = "configs.credentialTemplates.homelab.password"
      value = var.argocd_git_token
    }
  }
}

# Root app-of-apps. Applied with k3s kubectl on the guest so we do not need the
# Application CRD at terraform plan time (kubernetes_manifest would).
resource "terraform_data" "argocd_root_app" {
  count = local.k3s_alt_bootstrap_argocd ? 1 : 0

  depends_on = [helm_release.argocd]

  triggers_replace = [
    sha256(jsonencode(local.argocd_root_application)),
    try(helm_release.argocd[0].id, ""),
  ]

  connection {
    type    = "ssh"
    host    = local.k3s_alt_ip
    user    = var.ci_user
    agent   = true
    timeout = "10m"
  }

  provisioner "file" {
    content     = jsonencode(local.argocd_root_application)
    destination = "/tmp/argocd-root-application.json"
  }

  provisioner "remote-exec" {
    inline = [
      "set -euo pipefail",
      "until sudo k3s kubectl get crd applications.argoproj.io >/dev/null 2>&1; do sleep 5; done",
      "sudo k3s kubectl apply -f /tmp/argocd-root-application.json",
    ]
  }
}
