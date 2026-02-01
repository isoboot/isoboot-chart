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

if [ "$FAIL" -ne 0 ] || [ ! -s "$KNOWN_HOSTS" ]; then
  echo "FAIL: Cannot perform strict host key verification without valid public keys"
  exit 1
fi

# --- Verify SSH connects with strict host key checking ---
# SSH connects with StrictHostKeyChecking=yes using a known_hosts file
# built from the public keys we injected. If the VM's host keys don't
# match, SSH will refuse to connect and the test fails — proving the
# injected keys are actually in use by the SSH server.
echo ""
echo "Verifying SSH with strict host key checking..."

if sshpass -p "$PASSWORD" ssh \
  -o StrictHostKeyChecking=yes \
  -o UserKnownHostsFile="${KNOWN_HOSTS}" \
  -o ConnectTimeout=10 \
  "${USERNAME}@${IP}" "true"; then
  echo "OK: SSH connected with strict host key checking — host keys verified"
else
  echo "FAIL: SSH connection failed with strict host key checking (see SSH output above)"
  exit 1
fi

SSH_CMD=(sshpass -p "$PASSWORD" ssh
  -o StrictHostKeyChecking=yes
  -o UserKnownHostsFile="${KNOWN_HOSTS}"
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

# --- SSH host key hash verification (file integrity) ---
# In addition to the known_hosts check above (which proves the keys are
# functional for SSH trust), this compares SHA256 hashes to verify the
# key files were copied byte-for-byte.
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
