#!/usr/bin/env bash
set -euo pipefail

# Generates 3 SSH host keypairs and creates a Kubernetes Secret from them.
# Prints the secret name to stdout.
# $1 = case work directory (for storing the keypairs)

CASE_WORK="$1"

ssh-keygen -t ed25519 -f "${CASE_WORK}/ssh_host_ed25519_key" -N "" -q -C ""
ssh-keygen -t ecdsa -b 256 -f "${CASE_WORK}/ssh_host_ecdsa_key" -N "" -q -C ""
ssh-keygen -t rsa -b 4096 -f "${CASE_WORK}/ssh_host_rsa_key" -N "" -q -C ""

kubectl create secret generic pxe-test-secret -n isoboot \
  --from-file=ssh_host_ed25519_key="${CASE_WORK}/ssh_host_ed25519_key" \
  --from-file=ssh_host_ecdsa_key="${CASE_WORK}/ssh_host_ecdsa_key" \
  --from-file=ssh_host_rsa_key="${CASE_WORK}/ssh_host_rsa_key"

echo "pxe-test-secret"
