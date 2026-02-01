#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 5 ]; then
  echo "Usage: $0 <ip> <username> <password> <expected_hostname> <expected_domain>" >&2
  exit 1
fi

IP="$1"
USERNAME="$2"
PASSWORD="$3"
EXPECTED_HOSTNAME="$4"
EXPECTED_DOMAIN="$5"

SSH_CMD=(sshpass -p "$PASSWORD" ssh
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o ConnectTimeout=10
  "${USERNAME}@${IP}")

FAIL=0

# --- OS version ---
echo "Verifying Debian 13 (trixie) on ${IP}..."

OS_RELEASE=$("${SSH_CMD[@]}" "cat /etc/os-release")
echo "$OS_RELEASE"

if echo "$OS_RELEASE" | grep -q "VERSION_CODENAME=trixie"; then
  echo "OK: Debian 13 (trixie) confirmed"
else
  echo "FAIL: Expected VERSION_CODENAME=trixie"
  FAIL=1
fi

# --- Hostname ---
echo ""
echo "Verifying hostname..."

ACTUAL_HOSTNAME=$("${SSH_CMD[@]}" "hostname")
echo "  hostname: ${ACTUAL_HOSTNAME}"

if [ "$ACTUAL_HOSTNAME" = "$EXPECTED_HOSTNAME" ]; then
  echo "OK: hostname=${EXPECTED_HOSTNAME}"
else
  echo "FAIL: Expected hostname=${EXPECTED_HOSTNAME}, got ${ACTUAL_HOSTNAME}"
  FAIL=1
fi

# --- Domain ---
echo ""
echo "Verifying domain..."

ACTUAL_DOMAIN=$("${SSH_CMD[@]}" "dnsdomainname 2>/dev/null || echo ''")
echo "  domain: ${ACTUAL_DOMAIN}"

if [ "$ACTUAL_DOMAIN" = "$EXPECTED_DOMAIN" ]; then
  echo "OK: domain=${EXPECTED_DOMAIN}"
else
  echo "FAIL: Expected domain=${EXPECTED_DOMAIN}, got ${ACTUAL_DOMAIN}"
  FAIL=1
fi

exit "$FAIL"
