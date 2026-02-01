#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 6 ]; then
  echo "Usage: $0 <ip> <username> <password> <expected_hostname> <expected_domain> <case_work_dir>" >&2
  exit 1
fi

IP="$1"
USERNAME="$2"
PASSWORD="$3"
EXPECTED_HOSTNAME="$4"
EXPECTED_DOMAIN="$5"
CASE_WORK="$6"

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

# --- Machine ID ---
echo ""
echo "Verifying machine-id..."

EXPECTED_MACHINE_ID_FILE="${CASE_WORK}/expected-machine-id"
if [ ! -f "$EXPECTED_MACHINE_ID_FILE" ]; then
  echo "FAIL: Expected machine-id file not found at ${EXPECTED_MACHINE_ID_FILE}"
  FAIL=1
else
  # Compare raw file contents (should be exactly 33 bytes: 32 hex + newline)
  EXPECTED_SIZE=$(wc -c < "$EXPECTED_MACHINE_ID_FILE")
  echo "  expected size: ${EXPECTED_SIZE} bytes"

  if [ "$EXPECTED_SIZE" -ne 33 ]; then
    echo "FAIL: Expected machine-id file should be 33 bytes, got ${EXPECTED_SIZE}"
    FAIL=1
  fi

  ACTUAL_MACHINE_ID_FILE="${CASE_WORK}/actual-machine-id"
  "${SSH_CMD[@]}" "cat /etc/machine-id" > "$ACTUAL_MACHINE_ID_FILE"

  ACTUAL_SIZE=$(wc -c < "$ACTUAL_MACHINE_ID_FILE")
  echo "  actual size:   ${ACTUAL_SIZE} bytes"

  if [ "$ACTUAL_SIZE" -ne 33 ]; then
    echo "FAIL: Actual machine-id file should be 33 bytes, got ${ACTUAL_SIZE}"
    FAIL=1
  fi

  EXPECTED_MACHINE_ID=$(cat "$EXPECTED_MACHINE_ID_FILE")
  ACTUAL_MACHINE_ID=$(cat "$ACTUAL_MACHINE_ID_FILE")

  echo "  expected: ${EXPECTED_MACHINE_ID}"
  echo "  actual:   ${ACTUAL_MACHINE_ID}"

  if [ "$ACTUAL_MACHINE_ID" = "$EXPECTED_MACHINE_ID" ]; then
    echo "OK: machine-id matches"
  else
    echo "FAIL: machine-id mismatch"
    FAIL=1
  fi

  # Verify permissions (should be 444)
  PERMS=$("${SSH_CMD[@]}" "stat -c '%a' /etc/machine-id")
  echo "  permissions: ${PERMS}"

  if [ "$PERMS" = "444" ]; then
    echo "OK: machine-id permissions are 444"
  else
    echo "FAIL: Expected permissions 444, got ${PERMS}"
    FAIL=1
  fi
fi

exit "$FAIL"
