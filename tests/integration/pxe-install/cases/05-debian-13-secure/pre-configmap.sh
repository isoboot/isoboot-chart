#!/usr/bin/env bash
set -euo pipefail

# Generates an ed25519 keypair for SSH key auth testing.
# Prints extra --from-literal args to stdout for the ConfigMap.
# $1 = case work directory (for storing the private key)

CASE_WORK="$1"

ssh-keygen -t ed25519 -f "${CASE_WORK}/id_ed25519" -N "" -q
chmod 600 "${CASE_WORK}/id_ed25519"
PUBLIC_KEY=$(cat "${CASE_WORK}/id_ed25519.pub")

echo "--from-literal=sshPublicKey=${PUBLIC_KEY}"
