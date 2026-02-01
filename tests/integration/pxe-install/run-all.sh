#!/usr/bin/env bash
set -uo pipefail

# Runs all PXE install test cases sequentially. Each case boots a QEMU VM,
# installs Debian via PXE, and verifies the result. Continues on failure.
# Prints a summary table at the end.
#
# Expects setup.sh to have been run first (state in /tmp/pxe-install-test/state.env).
# Must be run as root.

if [ "$(id -u)" -ne 0 ]; then
  echo "Error: this script must be run as root." >&2
  exit 1
fi

WORK_DIR="/tmp/pxe-install-test"
STATE_FILE="${WORK_DIR}/state.env"
ARTIFACTS_DIR="${WORK_DIR}/artifacts"

if [ ! -f "$STATE_FILE" ]; then
  echo "ERROR: $STATE_FILE not found — run setup.sh first" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$STATE_FILE"

CASES_DIR="${SCRIPT_DIR}/cases"
INSTALL_TIMEOUT=600   # 10 min
SSH_TIMEOUT=300       # 5 min
QEMU_RAM="1G"
QEMU_DISK_SIZE="20G"

# Results tracking
declare -a CASE_NAMES=()
declare -a CASE_RESULTS=()

# ---------------------------------------------------------------------------
# Locate OVMF firmware (once)
# ---------------------------------------------------------------------------
OVMF_CODE=""
for candidate in \
  /usr/share/OVMF/OVMF_CODE_4M.fd \
  /usr/share/OVMF/OVMF_CODE.fd \
  /usr/share/edk2/ovmf/OVMF_CODE.fd \
  /usr/share/qemu/OVMF.fd; do
  if [ -f "$candidate" ]; then
    OVMF_CODE="$candidate"
    break
  fi
done
if [ -z "$OVMF_CODE" ]; then
  echo "ERROR: OVMF firmware not found"
  exit 1
fi

OVMF_VARS_SRC=""
for candidate in \
  /usr/share/OVMF/OVMF_VARS_4M.fd \
  /usr/share/OVMF/OVMF_VARS.fd \
  /usr/share/edk2/ovmf/OVMF_VARS.fd; do
  if [ -f "$candidate" ]; then
    OVMF_VARS_SRC="$candidate"
    break
  fi
done

echo "Using OVMF: $OVMF_CODE"

# ---------------------------------------------------------------------------
# run_case — runs a single test case
# ---------------------------------------------------------------------------
run_case() {
  local case_dir="$1"
  local case_num="$2"
  local case_name
  case_name="$(basename "$case_dir")"

  local case_work="${WORK_DIR}/${case_name}"
  local case_artifacts="${ARTIFACTS_DIR}/${case_name}"
  mkdir -p "$case_work" "$case_artifacts"

  echo ""
  echo "================================================================"
  echo "  CASE: ${case_name}"
  echo "================================================================"

  # --- Derive MAC from case number (52:54:00:XX:XX:XX) ---
  local vm_mac
  vm_mac=$(printf "52:54:00:%02d:%02d:%02d" \
    $(( case_num / 10000 % 100 )) $(( case_num / 100 % 100 )) $(( case_num % 100 )))
  local vm_mac_dash
  vm_mac_dash=$(echo "$vm_mac" | tr ':' '-')
  echo "MAC: ${vm_mac}"

  # --- Read case config (optional config.env in case dir) ---
  local provision_name="pxe-test-${case_name}"
  local boot_target="debian-13-no-firmware"
  local vm_name="pxe-test-vm.local"
  local username="isoboot"
  local expected_hostname="pxe-test-vm"
  local expected_domain="local"
  if [ -f "${case_dir}/config.env" ]; then
    # shellcheck disable=SC1091
    source "${case_dir}/config.env"
  fi

  # --- Generate credentials ---
  local password
  password=$(head -c 500 /dev/urandom | tr -dc a-z | cut -c1-16)
  local password_hash
  password_hash=$(openssl passwd -6 "$password")
  echo "Generated password for user '${username}'"

  # --- Run pre-configmap hook (optional) ---
  # The hook can generate files (e.g., SSH keys) in $case_work and print
  # extra --from-literal or --from-file args to stdout (one per line).
  local extra_cm_args=()
  if [ -f "${case_dir}/pre-configmap.sh" ]; then
    echo "Running pre-configmap hook..."
    mapfile -t extra_cm_args < <("${case_dir}/pre-configmap.sh" "$case_work")
  fi

  # --- Create ConfigMap ---
  echo "Creating ConfigMap..."
  kubectl create configmap "pxe-test-config" -n isoboot \
    --from-literal=language=en \
    --from-literal=country=US \
    --from-literal=keyboard=us \
    --from-literal=loginAsRoot=false \
    --from-literal=fullName=isoboot \
    --from-literal=username="$username" \
    --from-literal=password="$password_hash" \
    --from-literal=timezone=UTC \
    "${extra_cm_args[@]+"${extra_cm_args[@]}"}"

  # --- Apply fixtures (substitute MAC placeholder) ---
  echo "Applying fixtures..."
  sed "s/\${MAC}/${vm_mac_dash}/g" "${case_dir}/fixtures.yaml" | kubectl apply -f -

  # --- Create Provision ---
  echo "Creating Provision..."
  kubectl apply -f - <<EOF
apiVersion: isoboot.io/v1alpha1
kind: Provision
metadata:
  name: ${provision_name}
  namespace: isoboot
spec:
  machineRef: ${vm_name}
  bootTargetRef: ${boot_target}
  responseTemplateRef: pxe-test-preseed
  configMaps:
    - pxe-test-config
EOF

  # --- Create QEMU disk ---
  local disk="${case_work}/disk.qcow2"
  qemu-img create -f qcow2 "$disk" "$QEMU_DISK_SIZE"

  # --- Create tap device ---
  ip link del tap-vm 2>/dev/null || true
  ip tuntap add dev tap-vm mode tap
  ip link set tap-vm master "$BRIDGE"
  ip link set tap-vm up

  # --- Copy OVMF vars ---
  local pflash_args=( -drive "if=pflash,format=raw,readonly=on,file=${OVMF_CODE}" )
  if [ -n "$OVMF_VARS_SRC" ]; then
    cp "$OVMF_VARS_SRC" "${case_work}/ovmf_vars.fd"
    pflash_args+=( -drive "if=pflash,format=raw,file=${case_work}/ovmf_vars.fd" )
  fi

  # --- Launch QEMU ---
  local serial_log="${case_work}/serial.log"
  echo "Launching QEMU..."
  qemu-system-x86_64 \
    -enable-kvm \
    -m "$QEMU_RAM" \
    -cpu host \
    -smp 2 \
    -drive "file=${disk},format=qcow2,if=virtio" \
    "${pflash_args[@]}" \
    -netdev "tap,id=net0,ifname=tap-vm,script=no,downscript=no" \
    -device "virtio-net-pci,netdev=net0,mac=${vm_mac}" \
    -serial "file:${serial_log}" \
    -display none \
    -pidfile "${case_work}/qemu.pid" \
    -daemonize

  sleep 2
  local qemu_pid
  qemu_pid=$(cat "${case_work}/qemu.pid" 2>/dev/null || true)
  if [ -z "$qemu_pid" ] || ! kill -0 "$qemu_pid" 2>/dev/null; then
    echo "ERROR: QEMU failed to start"
    cp "$serial_log" "$case_artifacts/" 2>/dev/null || true
    return 1
  fi
  echo "QEMU started (PID $qemu_pid)"

  # --- Poll Provision until Complete ---
  echo "Waiting for Provision to complete (timeout: ${INSTALL_TIMEOUT}s)..."
  local elapsed=0
  local poll_interval=30
  while [ "$elapsed" -lt "$INSTALL_TIMEOUT" ]; do
    local status
    status=$(kubectl get provision/"${provision_name}" -n isoboot \
      -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    local disk_size
    disk_size=$(du -sm "$disk" 2>/dev/null | awk '{print $1}' || echo "?")
    echo "  [${elapsed}s] status=${status}  disk=${disk_size}MB"

    if [ "$status" = "Complete" ]; then
      echo "Provision is Complete!"
      break
    fi

    if [ "$status" = "Failed" ] || [ "$status" = "ConfigError" ]; then
      local msg
      msg=$(kubectl get provision/"${provision_name}" -n isoboot \
        -o jsonpath='{.status.message}' 2>/dev/null || echo "")
      echo "ERROR: Provision ${status}: ${msg}"
      cp "$serial_log" "$case_artifacts/" 2>/dev/null || true
      kill "$qemu_pid" 2>/dev/null || true
      wait "$qemu_pid" 2>/dev/null || true
      ip link del tap-vm 2>/dev/null || true
      return 1
    fi

    if ! kill -0 "$qemu_pid" 2>/dev/null; then
      echo "ERROR: QEMU process exited unexpectedly"
      cp "$serial_log" "$case_artifacts/" 2>/dev/null || true
      ip link del tap-vm 2>/dev/null || true
      return 1
    fi

    sleep "$poll_interval"
    elapsed=$((elapsed + poll_interval))
  done

  if [ "$elapsed" -ge "$INSTALL_TIMEOUT" ]; then
    echo "ERROR: Provision did not complete within ${INSTALL_TIMEOUT}s"
    cp "$serial_log" "$case_artifacts/" 2>/dev/null || true
    kill "$qemu_pid" 2>/dev/null || true
    wait "$qemu_pid" 2>/dev/null || true
    ip link del tap-vm 2>/dev/null || true
    return 1
  fi

  # --- Get VM IP from ARP table (by MAC address) ---
  local vm_ip=""
  local arp_wait=0
  echo "Looking up VM IP from ARP table (MAC: ${vm_mac})..."
  while [ "$arp_wait" -lt 60 ]; do
    vm_ip=$(ip neigh show dev "$BRIDGE" \
      | grep -i "$vm_mac" \
      | awk '{print $1}' \
      | head -1 || true)
    if [ -n "$vm_ip" ]; then
      break
    fi
    sleep 5
    arp_wait=$((arp_wait + 5))
  done
  if [ -z "$vm_ip" ]; then
    echo "ERROR: Could not find VM IP in ARP table for MAC ${vm_mac}"
    cp "$serial_log" "$case_artifacts/" 2>/dev/null || true
    kill "$qemu_pid" 2>/dev/null || true
    wait "$qemu_pid" 2>/dev/null || true
    ip link del tap-vm 2>/dev/null || true
    return 1
  fi
  echo "VM IP: ${vm_ip}"

  # --- Wait for SSH ---
  echo "Waiting for SSH on ${vm_ip}..."
  elapsed=0
  while [ "$elapsed" -lt "$SSH_TIMEOUT" ]; do
    if sshpass -p "$password" ssh \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      -o ConnectTimeout=5 \
      "${username}@${vm_ip}" "true" 2>/dev/null; then
      echo "SSH is available!"
      break
    fi
    sleep 10
    elapsed=$((elapsed + 10))
    echo "  [${elapsed}s] Waiting for SSH..."
  done

  if [ "$elapsed" -ge "$SSH_TIMEOUT" ]; then
    echo "ERROR: SSH did not become available within ${SSH_TIMEOUT}s"
    cp "$serial_log" "$case_artifacts/" 2>/dev/null || true
    kill "$qemu_pid" 2>/dev/null || true
    wait "$qemu_pid" 2>/dev/null || true
    ip link del tap-vm 2>/dev/null || true
    return 1
  fi

  # --- Run verify script ---
  echo "Running verify script..."
  if ! "${case_dir}/verify.sh" "$vm_ip" "$username" "$password" "$expected_hostname" "$expected_domain" "$case_work"; then
    echo "ERROR: Verification failed"
    cp "$serial_log" "$case_artifacts/" 2>/dev/null || true
    kill "$qemu_pid" 2>/dev/null || true
    wait "$qemu_pid" 2>/dev/null || true
    ip link del tap-vm 2>/dev/null || true
    return 1
  fi

  # --- Power off VM ---
  echo "Powering off VM..."
  sshpass -p "$password" ssh \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    "${username}@${vm_ip}" \
    "echo '${password}' | sudo -S poweroff" 2>/dev/null || true

  elapsed=0
  while [ "$elapsed" -lt 60 ] && kill -0 "$qemu_pid" 2>/dev/null; do
    sleep 2
    elapsed=$((elapsed + 2))
  done
  if kill -0 "$qemu_pid" 2>/dev/null; then
    kill -9 "$qemu_pid" 2>/dev/null || true
  fi

  # --- Cleanup per-case resources ---
  ip link del tap-vm 2>/dev/null || true

  return 0
}

# ---------------------------------------------------------------------------
# cleanup_case — deletes Kubernetes resources for a case
# ---------------------------------------------------------------------------
cleanup_case() {
  local case_name="$1"
  local provision_name="pxe-test-${case_name}"

  echo "Cleaning up resources for ${case_name}..."
  kubectl delete provision/"${provision_name}" -n isoboot --ignore-not-found --wait 2>/dev/null || true
  kubectl delete responsetemplate/pxe-test-preseed -n isoboot --ignore-not-found --wait 2>/dev/null || true
  kubectl delete machine/pxe-test-vm.local -n isoboot --ignore-not-found --wait 2>/dev/null || true
  kubectl delete configmap/pxe-test-config -n isoboot --ignore-not-found --wait 2>/dev/null || true

  # Kill any leftover QEMU
  local case_work="${WORK_DIR}/${case_name}"
  if [ -f "${case_work}/qemu.pid" ]; then
    local pid
    pid=$(cat "${case_work}/qemu.pid" 2>/dev/null || true)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      kill -9 "$pid" 2>/dev/null || true
    fi
  fi

  # Remove tap device
  ip link del tap-vm 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Main — discover and run all cases
# ---------------------------------------------------------------------------
mkdir -p "$ARTIFACTS_DIR"

mapfile -t cases < <(find "$CASES_DIR" -mindepth 1 -maxdepth 1 -type d | sort)

if [ ${#cases[@]} -eq 0 ]; then
  echo "ERROR: No test cases found in $CASES_DIR"
  exit 1
fi

echo "Found ${#cases[@]} test case(s):"
for c in "${cases[@]}"; do
  echo "  - $(basename "$c")"
done

TOTAL=${#cases[@]}
PASSED=0
FAILED=0

for case_dir in "${cases[@]}"; do
  case_name="$(basename "$case_dir")"
  # Extract case number from directory name prefix (e.g., 01 from 01-basic-debian-13)
  case_num=$((10#${case_name%%-*}))
  CASE_NAMES+=("$case_name")

  if run_case "$case_dir" "$case_num"; then
    CASE_RESULTS+=("PASS")
    PASSED=$((PASSED + 1))
  else
    CASE_RESULTS+=("FAIL")
    FAILED=$((FAILED + 1))
  fi

  cleanup_case "$case_name"
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "================================================================"
echo "  PXE Install Test Results"
echo "================================================================"

max_len=0
for name in "${CASE_NAMES[@]}"; do
  [ ${#name} -gt $max_len ] && max_len=${#name}
done

for i in "${!CASE_NAMES[@]}"; do
  printf "  %-${max_len}s  %s\n" "${CASE_NAMES[$i]}" "${CASE_RESULTS[$i]}"
done

echo "================================================================"
echo "  ${PASSED}/${TOTAL} passed, ${FAILED}/${TOTAL} failed"
echo "================================================================"

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
