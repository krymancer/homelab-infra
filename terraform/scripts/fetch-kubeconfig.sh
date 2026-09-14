#!/usr/bin/env bash
# Copy k3s admin kubeconfig from the guest and rewrite the API server to the LAN IP.
set -euo pipefail

usage() {
  echo "usage: $0 <ssh-user> <host> <output-path>" >&2
  exit 2
}

[[ $# -eq 3 ]] || usage

user="$1"
host="$2"
out="$3"

mkdir -p "$(dirname "$out")"

ssh \
  -o BatchMode=yes \
  -o StrictHostKeyChecking=accept-new \
  -o ConnectTimeout=10 \
  "${user}@${host}" \
  "sudo cat /etc/rancher/k3s/k3s.yaml" \
  | sed "s#https://127.0.0.1:6443#https://${host}:6443#g" \
    >"${out}.tmp"

chmod 600 "${out}.tmp"
mv "${out}.tmp" "${out}"
echo "wrote kubeconfig to ${out}"
