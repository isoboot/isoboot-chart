#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 3 ]; then
  echo "Usage: $0 <ip> <username> <password>" >&2
  exit 1
fi

IP="$1"
USERNAME="$2"
PASSWORD="$3"

echo "Verifying Debian 13 (trixie) on ${IP}..."

OS_RELEASE=$(sshpass -p "$PASSWORD" ssh \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -o ConnectTimeout=10 \
  "${USERNAME}@${IP}" "cat /etc/os-release")

echo "$OS_RELEASE"

if echo "$OS_RELEASE" | grep -q "VERSION_CODENAME=trixie"; then
  echo "OK: Debian 13 (trixie) confirmed"
  exit 0
else
  echo "FAIL: Expected VERSION_CODENAME=trixie"
  exit 1
fi
