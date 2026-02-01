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

FAIL=0

# --- Build known_hosts from injected public keys ---
echo "Building known_hosts from injected public keys..."

KNOWN_HOSTS="${CASE_WORK}/known_hosts"
rm -f "$KNOWN_HOSTS"
for key_type in ed25519 ecdsa rsa; do
  PUB_FILE="${CASE_WORK}/ssh_host_${key_type}_key.pub"
  if [ ! -f "$PUB_FILE" ]; then
    echo "FAIL: Public key not found at ${PUB_FILE}"
    FAIL=1
    continue
  fi
  KEY_DATA=$(awk '{print $1, $2}' "$PUB_FILE")
  echo "${IP} ${KEY_DATA}" >> "$KNOWN_HOSTS"
done

chmod 644 "$KNOWN_HOSTS" 2>/dev/null || true

if [ "$FAIL" -ne 0 ] || [ ! -s "$KNOWN_HOSTS" ]; then
  echo "FAIL: Cannot perform strict host key verification without valid public keys"
  exit 1
fi

# --- Verify password authentication is REJECTED ---
echo ""
echo "Verifying password authentication is rejected..."

if sshpass -p "$PASSWORD" ssh \
  -o StrictHostKeyChecking=yes \
  -o UserKnownHostsFile="${KNOWN_HOSTS}" \
  -o GlobalKnownHostsFile=/dev/null \
  -o ConnectTimeout=10 \
  -o PubkeyAuthentication=no \
  -o PreferredAuthentications=password \
  "${USERNAME}@${IP}" "true" 2>/dev/null; then
  echo "FAIL: Password authentication should be rejected but succeeded"
  FAIL=1
else
  echo "OK: Password authentication correctly rejected"
fi

# --- Verify key-only authentication SUCCEEDS ---
echo ""
echo "Verifying SSH key authentication with strict host key checking..."

KEY_FILE="${CASE_WORK}/id_ed25519"
if [ ! -f "$KEY_FILE" ]; then
  echo "FAIL: Private key not found at ${KEY_FILE}"
  FAIL=1
else
  if ssh -i "$KEY_FILE" \
    -o StrictHostKeyChecking=yes \
    -o UserKnownHostsFile="${KNOWN_HOSTS}" \
    -o GlobalKnownHostsFile=/dev/null \
    -o ConnectTimeout=10 \
    -o PasswordAuthentication=no \
    -o PreferredAuthentications=publickey \
    "${USERNAME}@${IP}" "true" 2>/dev/null; then
    echo "OK: SSH key authentication works with strict host key checking"
  else
    echo "FAIL: SSH key authentication failed"
    FAIL=1
  fi
fi

# --- Set up SSH command using key auth + known_hosts ---
SSH_CMD=(ssh -i "${CASE_WORK}/id_ed25519"
  -o StrictHostKeyChecking=yes
  -o UserKnownHostsFile="${KNOWN_HOSTS}"
  -o GlobalKnownHostsFile=/dev/null
  -o ConnectTimeout=10
  "${USERNAME}@${IP}")

# --- OS version ---
echo ""
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

# --- SSH host key hash verification (file integrity) ---
echo ""
echo "Verifying SSH host key file integrity (SHA256)..."

for key_type in ed25519 ecdsa rsa; do
  echo ""
  echo "  Checking ssh_host_${key_type}_key..."

  key_file="${CASE_WORK}/ssh_host_${key_type}_key"
  if [ ! -f "$key_file" ]; then
    echo "  FAIL: Local key not found at ${key_file}"
    FAIL=1
    continue
  fi

  key_hash=$(sha256sum "$key_file" | awk '{print $1}')
  remote_hash=$("${SSH_CMD[@]}" "echo '${PASSWORD}' | sudo -S sha256sum /etc/ssh/ssh_host_${key_type}_key 2>/dev/null | awk '{print \$1}'")

  echo "    local:  ${key_hash}"
  echo "    remote: ${remote_hash}"

  if [ "$key_hash" = "$remote_hash" ]; then
    echo "  OK: ssh_host_${key_type}_key matches"
  else
    echo "  FAIL: ssh_host_${key_type}_key mismatch"
    FAIL=1
  fi
done

exit "$FAIL"
