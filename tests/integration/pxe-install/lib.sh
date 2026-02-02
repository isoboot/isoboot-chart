#!/usr/bin/env bash
# Shared verification functions for PXE install tests.
# Source this from verify.sh: source "$(dirname "$0")/lib.sh"

FAIL=0

# --- Argument parsing ---

parse_args() {
  if [ "$#" -lt 5 ]; then
    echo "Usage: $0 <ip> <username> <password> <expected_hostname> <expected_domain> [<case_work_dir>]" >&2
    exit 1
  fi
  IP="$1"
  USERNAME="$2"
  PASSWORD="$3"
  EXPECTED_HOSTNAME="$4"
  EXPECTED_DOMAIN="$5"
  CASE_WORK="${6:-}"
}

# --- SSH command setup ---

# Password-based SSH (no host key verification)
setup_password_ssh() {
  SSH_CMD=(sshpass -p "$PASSWORD" ssh
    -o StrictHostKeyChecking=no
    -o UserKnownHostsFile=/dev/null
    -o ConnectTimeout=10
    "${USERNAME}@${IP}")
}

# Password-based SSH with strict known_hosts verification
setup_password_ssh_strict() {
  local known_hosts="$1"
  SSH_CMD=(sshpass -p "$PASSWORD" ssh
    -o StrictHostKeyChecking=yes
    -o UserKnownHostsFile="$known_hosts"
    -o GlobalKnownHostsFile=/dev/null
    -o ConnectTimeout=10
    "${USERNAME}@${IP}")
}

# Key-based SSH with strict known_hosts verification (non-interactive)
setup_key_ssh_strict() {
  local key_file="$1"
  local known_hosts="$2"
  SSH_CMD=(ssh -i "$key_file"
    -o StrictHostKeyChecking=yes
    -o UserKnownHostsFile="$known_hosts"
    -o GlobalKnownHostsFile=/dev/null
    -o ConnectTimeout=10
    -o BatchMode=yes
    -o PreferredAuthentications=publickey
    "${USERNAME}@${IP}")
}

# --- Known hosts ---

# Build known_hosts file from injected SSH host public keys.
# Exits with status 1 if any public key is missing.
build_known_hosts() {
  local known_hosts_file="$1"

  echo "Building known_hosts from injected public keys..."
  rm -f "$known_hosts_file"

  for key_type in ed25519 ecdsa rsa; do
    local pub_file="${CASE_WORK}/ssh_host_${key_type}_key.pub"
    if [ ! -f "$pub_file" ]; then
      echo "FAIL: Public key not found at ${pub_file}"
      FAIL=1
      continue
    fi
    local key_data
    key_data=$(awk '{print $1, $2}' "$pub_file")
    echo "${IP} ${key_data}" >> "$known_hosts_file"
  done

  chmod 644 "$known_hosts_file" 2>/dev/null || true

  if [ "$FAIL" -ne 0 ] || [ ! -s "$known_hosts_file" ]; then
    echo "FAIL: Cannot perform strict host key verification without valid public keys"
    exit 1
  fi
}

# --- Verification functions ---

verify_os_version() {
  local codename="${EXPECTED_CODENAME:?EXPECTED_CODENAME not set}"
  echo ""
  echo "Verifying ${codename} on ${IP}..."

  local os_release
  os_release=$("${SSH_CMD[@]}" "cat /etc/os-release")
  echo "$os_release"

  if echo "$os_release" | grep -q "VERSION_CODENAME=${codename}"; then
    echo "OK: ${codename} confirmed"
  else
    echo "FAIL: Expected VERSION_CODENAME=${codename}"
    FAIL=1
  fi
}

verify_hostname() {
  echo ""
  echo "Verifying hostname..."

  local actual_hostname
  actual_hostname=$("${SSH_CMD[@]}" "hostname")
  echo "  hostname: ${actual_hostname}"

  if [ "$actual_hostname" = "$EXPECTED_HOSTNAME" ]; then
    echo "OK: hostname=${EXPECTED_HOSTNAME}"
  else
    echo "FAIL: Expected hostname=${EXPECTED_HOSTNAME}, got ${actual_hostname}"
    FAIL=1
  fi
}

verify_domain() {
  echo ""
  echo "Verifying domain..."

  local actual_domain
  actual_domain=$("${SSH_CMD[@]}" "dnsdomainname 2>/dev/null || echo ''")
  echo "  domain: ${actual_domain}"

  if [ "$actual_domain" = "$EXPECTED_DOMAIN" ]; then
    echo "OK: domain=${EXPECTED_DOMAIN}"
  else
    echo "FAIL: Expected domain=${EXPECTED_DOMAIN}, got ${actual_domain}"
    FAIL=1
  fi
}

# Verify password-based SSH authentication succeeds
verify_ssh_password_auth() {
  echo ""
  echo "Verifying SSH password authentication..."

  if sshpass -p "$PASSWORD" ssh \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=10 \
    -o PubkeyAuthentication=no \
    "${USERNAME}@${IP}" "true" 2>/dev/null; then
    echo "OK: SSH password authentication works"
  else
    echo "FAIL: SSH password authentication failed"
    FAIL=1
  fi
}

# Verify key-based SSH authentication succeeds.
# Args: [key_file] [known_hosts_file]
#   key_file       - path to private key (default: ${CASE_WORK}/id_ed25519)
#   known_hosts    - if set, use StrictHostKeyChecking=yes with this file
verify_ssh_key_auth() {
  local key_file="${1:-${CASE_WORK}/id_ed25519}"
  local known_hosts="${2:-}"

  echo ""
  if [ -n "$known_hosts" ]; then
    echo "Verifying SSH key authentication with strict host key checking..."
  else
    echo "Verifying SSH key authentication..."
  fi

  if [ ! -f "$key_file" ]; then
    echo "FAIL: Private key not found at ${key_file}"
    FAIL=1
    return
  fi

  local ssh_opts=(-i "$key_file"
    -o ConnectTimeout=10
    -o BatchMode=yes
    -o PasswordAuthentication=no
    -o PreferredAuthentications=publickey)

  if [ -n "$known_hosts" ]; then
    ssh_opts+=(
      -o StrictHostKeyChecking=yes
      -o UserKnownHostsFile="$known_hosts"
      -o GlobalKnownHostsFile=/dev/null)
  else
    ssh_opts+=(
      -o StrictHostKeyChecking=no
      -o UserKnownHostsFile=/dev/null)
  fi

  if ssh "${ssh_opts[@]}" "${USERNAME}@${IP}" "true" 2>/dev/null; then
    if [ -n "$known_hosts" ]; then
      echo "OK: SSH key authentication works with strict host key checking"
    else
      echo "OK: SSH key authentication works"
    fi
  else
    echo "FAIL: SSH key authentication failed"
    FAIL=1
  fi
}

# Verify password-based SSH authentication is rejected.
# Args: [known_hosts_file]
#   known_hosts - if set, use StrictHostKeyChecking=yes with this file
verify_password_rejected() {
  local known_hosts="${1:-}"

  echo ""
  echo "Verifying password authentication is rejected..."

  local ssh_opts=(
    -o ConnectTimeout=10
    -o PubkeyAuthentication=no
    -o PreferredAuthentications=password)

  if [ -n "$known_hosts" ]; then
    ssh_opts+=(
      -o StrictHostKeyChecking=yes
      -o UserKnownHostsFile="$known_hosts"
      -o GlobalKnownHostsFile=/dev/null)
  else
    ssh_opts+=(
      -o StrictHostKeyChecking=no
      -o UserKnownHostsFile=/dev/null)
  fi

  local ssh_output ssh_status
  set +e
  ssh_output=$(sshpass -p "$PASSWORD" ssh "${ssh_opts[@]}" "${USERNAME}@${IP}" "true" 2>&1)
  ssh_status=$?
  set -e

  if [ "$ssh_status" -eq 0 ]; then
    echo "FAIL: Password authentication should be rejected but succeeded"
    FAIL=1
  elif echo "$ssh_output" | grep -qi "permission denied"; then
    echo "OK: Password authentication correctly rejected (permission denied)"
  else
    echo "FAIL: SSH with password failed for an unexpected reason:"
    echo "$ssh_output"
    FAIL=1
  fi
}

# Verify machine-id content and permissions (444).
verify_machine_id() {
  echo ""
  echo "Verifying machine-id..."

  local expected_file="${CASE_WORK}/expected-machine-id"
  if [ ! -f "$expected_file" ]; then
    echo "FAIL: Expected machine-id file not found at ${expected_file}"
    FAIL=1
    return
  fi

  local expected_size
  expected_size=$(wc -c < "$expected_file")
  echo "  expected size: ${expected_size} bytes"

  if [ "$expected_size" -ne 33 ]; then
    echo "FAIL: Expected machine-id file should be 33 bytes, got ${expected_size}"
    FAIL=1
  fi

  local actual_file="${CASE_WORK}/actual-machine-id"
  "${SSH_CMD[@]}" "cat /etc/machine-id" > "$actual_file"

  local actual_size
  actual_size=$(wc -c < "$actual_file")
  echo "  actual size:   ${actual_size} bytes"

  if [ "$actual_size" -ne 33 ]; then
    echo "FAIL: Actual machine-id file should be 33 bytes, got ${actual_size}"
    FAIL=1
  fi

  local expected_id actual_id
  expected_id=$(cat "$expected_file")
  actual_id=$(cat "$actual_file")

  echo "  expected: ${expected_id}"
  echo "  actual:   ${actual_id}"

  if [ "$actual_id" = "$expected_id" ]; then
    echo "OK: machine-id matches"
  else
    echo "FAIL: machine-id mismatch"
    FAIL=1
  fi

  local perms
  perms=$("${SSH_CMD[@]}" "stat -c '%a' /etc/machine-id")
  echo "  permissions: ${perms}"

  if [ "$perms" = "444" ]; then
    echo "OK: machine-id permissions are 444"
  else
    echo "FAIL: Expected permissions 444, got ${perms}"
    FAIL=1
  fi
}

# Verify SSH host key files match by SHA256 hash (byte-for-byte integrity).
verify_host_key_hashes() {
  echo ""
  echo "Verifying SSH host key file integrity (SHA256)..."

  for key_type in ed25519 ecdsa rsa; do
    echo ""
    echo "  Checking ssh_host_${key_type}_key..."

    local key_file="${CASE_WORK}/ssh_host_${key_type}_key"
    if [ ! -f "$key_file" ]; then
      echo "  FAIL: Local key not found at ${key_file}"
      FAIL=1
      continue
    fi

    local key_hash remote_hash
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
}
