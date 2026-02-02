#!/usr/bin/env bash
set -uo pipefail

# Runs a single PXE install test for a given distro/version. Boots a QEMU VM,
# installs the OS via PXE, and verifies the result.
#
# Usage: sudo run.sh <distro> <version> <codename> <boot_target>
#
# Expects setup.sh to have been run first (state in /tmp/pxe-install-test/state.env).
# Must be run as root.

if [ "$(id -u)" -ne 0 ]; then
  echo "Error: this script must be run as root." >&2
  exit 1
fi

if [ "$#" -ne 4 ]; then
  echo "Usage: $0 <distro> <version> <codename> <boot_target>" >&2
  exit 1
fi

DISTRO="$1"
VERSION="$2"
CODENAME="$3"
BOOT_TARGET="$4"

WORK_DIR="/tmp/pxe-install-test"
STATE_FILE="${WORK_DIR}/state.env"

if [ ! -f "$STATE_FILE" ]; then
  echo "ERROR: $STATE_FILE not found — run setup.sh first" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$STATE_FILE"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

INSTALL_TIMEOUT=600   # 10 min
SSH_TIMEOUT=300       # 5 min
QEMU_RAM="1G"
QEMU_DISK_SIZE="20G"

# --- Resource names ---
PROVISION="pxe-test-${DISTRO}-${VERSION}"
VM_NAME="pxe-test-${DISTRO}-${VERSION}.local"
CONFIGMAP="pxe-test-config"
PRESEED="pxe-test-preseed"
SECRET_BASE="pxe-test-secret"
TAP="tap-1"
MAC="52:54:00:00:00:01"
MAC_DASH="52-54-00-00-00-01"
USERNAME="isoboot"
EXPECTED_HOSTNAME="pxe-test-${DISTRO}-${VERSION}"
EXPECTED_DOMAIN="local"

CASE_WORK="${WORK_DIR}/${DISTRO}-${VERSION}"
ARTIFACTS_DIR="${WORK_DIR}/artifacts"
mkdir -p "$CASE_WORK" "$ARTIFACTS_DIR"

echo ""
echo "================================================================"
echo "  PXE Install Test: ${DISTRO} ${VERSION} (${CODENAME})"
echo "================================================================"
echo "  Boot target: ${BOOT_TARGET}"
echo "  VM name:     ${VM_NAME}"
echo "  MAC:         ${MAC}"
echo ""

# ---------------------------------------------------------------------------
# Locate OVMF firmware
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
# Generate credentials
# ---------------------------------------------------------------------------
PASSWORD=$(head -c 500 /dev/urandom | tr -dc a-z | cut -c1-16)
PASSWORD_HASH=$(openssl passwd -6 "$PASSWORD")
echo "Generated password for user '${USERNAME}'"

# ---------------------------------------------------------------------------
# Run hooks
# ---------------------------------------------------------------------------
extra_cm_args=()
if [ -f "${SCRIPT_DIR}/pre-configmap.sh" ]; then
  echo "Running pre-configmap hook..."
  mapfile -t extra_cm_args < <("${SCRIPT_DIR}/pre-configmap.sh" "$CASE_WORK")
fi

secret_name=""
if [ -f "${SCRIPT_DIR}/pre-secret.sh" ]; then
  echo "Running pre-secret hook..."
  secret_name=$("${SCRIPT_DIR}/pre-secret.sh" "$CASE_WORK" "$SECRET_BASE")
fi

extra_provision_spec=""
if [ -f "${SCRIPT_DIR}/pre-provision.sh" ]; then
  echo "Running pre-provision hook..."
  extra_provision_spec=$("${SCRIPT_DIR}/pre-provision.sh" "$CASE_WORK")
fi

# ---------------------------------------------------------------------------
# Create ConfigMap
# ---------------------------------------------------------------------------
echo "Creating ConfigMap ${CONFIGMAP}..."
kubectl create configmap "$CONFIGMAP" -n isoboot \
  --from-literal=language=en \
  --from-literal=country=US \
  --from-literal=keyboard=us \
  --from-literal=loginAsRoot=false \
  --from-literal=fullName=isoboot \
  --from-literal=username="$USERNAME" \
  --from-literal=password="$PASSWORD_HASH" \
  --from-literal=timezone=UTC \
  "${extra_cm_args[@]+"${extra_cm_args[@]}"}"

# ---------------------------------------------------------------------------
# Apply fixtures (distro-specific)
# ---------------------------------------------------------------------------
FIXTURES="${SCRIPT_DIR}/fixtures/${DISTRO}.yaml"
if [ ! -f "$FIXTURES" ]; then
  echo "ERROR: Fixtures not found: ${FIXTURES}"
  exit 1
fi

echo "Applying fixtures from ${FIXTURES}..."
sed -e "s/\${MAC}/${MAC_DASH}/g" \
    -e "s/\${VM_NAME}/${VM_NAME}/g" \
    "$FIXTURES" | kubectl apply -f -

# ---------------------------------------------------------------------------
# Create Provision
# ---------------------------------------------------------------------------
echo "Creating Provision ${PROVISION}..."
kubectl apply -f - <<EOF
apiVersion: isoboot.io/v1alpha1
kind: Provision
metadata:
  name: ${PROVISION}
  namespace: isoboot
spec:
  machineRef: ${VM_NAME}
  bootTargetRef: ${BOOT_TARGET}
  responseTemplateRef: ${PRESEED}
  configMaps:
    - ${CONFIGMAP}
$([ -n "$secret_name" ] && echo "  secrets:
    - ${secret_name}")
${extra_provision_spec}
EOF

# ---------------------------------------------------------------------------
# Verify resources before launching VM
# ---------------------------------------------------------------------------
if [ -n "$secret_name" ]; then
  echo "Verifying secret '${secret_name}'..."
  kubectl get secret/"${secret_name}" -n isoboot \
    -o go-template='{{range $k, $v := .data}}  key: {{$k}} ({{len $v}} chars base64){{"\n"}}{{end}}'
fi

echo "Verifying preseed rendering..."
preseed_url="http://${KIND_IP}:8080/dynamic/answer/${PROVISION}/preseed.cfg"
http_code=$(curl -s -o "${CASE_WORK}/rendered-preseed.cfg" -w '%{http_code}' "$preseed_url" 2>/dev/null || echo "000")
if [ "$http_code" = "200" ]; then
  echo "  Preseed rendered OK ($(wc -c < "${CASE_WORK}/rendered-preseed.cfg") bytes)"
  cp "${CASE_WORK}/rendered-preseed.cfg" "${ARTIFACTS_DIR}/"
else
  echo "  WARNING: Preseed rendering returned HTTP ${http_code} (URL: ${preseed_url})"
  head -5 "${CASE_WORK}/rendered-preseed.cfg" 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# Create QEMU disk
# ---------------------------------------------------------------------------
DISK="${CASE_WORK}/disk.qcow2"
qemu-img create -f qcow2 "$DISK" "$QEMU_DISK_SIZE"

# ---------------------------------------------------------------------------
# Create tap device
# ---------------------------------------------------------------------------
ip link del "$TAP" 2>/dev/null || true
ip tuntap add dev "$TAP" mode tap
ip link set "$TAP" master "$BRIDGE"
ip link set "$TAP" up

# ---------------------------------------------------------------------------
# Launch QEMU
# ---------------------------------------------------------------------------
pflash_args=( -drive "if=pflash,format=raw,readonly=on,file=${OVMF_CODE}" )
if [ -n "$OVMF_VARS_SRC" ]; then
  cp "$OVMF_VARS_SRC" "${CASE_WORK}/ovmf_vars.fd"
  pflash_args+=( -drive "if=pflash,format=raw,file=${CASE_WORK}/ovmf_vars.fd" )
fi

SERIAL_LOG="${CASE_WORK}/serial.log"
echo "Launching QEMU..."
qemu-system-x86_64 \
  -enable-kvm \
  -m "$QEMU_RAM" \
  -cpu host \
  -smp 2 \
  -drive "file=${DISK},format=qcow2,if=virtio" \
  "${pflash_args[@]}" \
  -netdev "tap,id=net0,ifname=${TAP},script=no,downscript=no" \
  -device "virtio-net-pci,netdev=net0,mac=${MAC}" \
  -serial "file:${SERIAL_LOG}" \
  -display none \
  -pidfile "${CASE_WORK}/qemu.pid" \
  -daemonize

sleep 2
QEMU_PID=$(cat "${CASE_WORK}/qemu.pid" 2>/dev/null || true)
if [ -z "$QEMU_PID" ] || ! kill -0 "$QEMU_PID" 2>/dev/null; then
  echo "ERROR: QEMU failed to start"
  cp "$SERIAL_LOG" "$ARTIFACTS_DIR/" 2>/dev/null || true
  exit 1
fi
echo "QEMU started (PID $QEMU_PID)"

# ---------------------------------------------------------------------------
# Poll Provision until Complete
# ---------------------------------------------------------------------------
echo "Waiting for Provision to complete (timeout: ${INSTALL_TIMEOUT}s)..."
elapsed=0
poll_interval=30
while [ "$elapsed" -lt "$INSTALL_TIMEOUT" ]; do
  status=$(kubectl get provision/"${PROVISION}" -n isoboot \
    -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
  disk_size=$(du -sm "$DISK" 2>/dev/null | awk '{print $1}' || echo "?")
  echo "  [${elapsed}s] status=${status}  disk=${disk_size}MB"

  if [ "$status" = "Complete" ]; then
    echo "Provision is Complete!"
    break
  fi

  if [ "$status" = "Failed" ] || [ "$status" = "ConfigError" ]; then
    msg=$(kubectl get provision/"${PROVISION}" -n isoboot \
      -o jsonpath='{.status.message}' 2>/dev/null || echo "")
    echo "ERROR: Provision ${status}: ${msg}"
    cp "$SERIAL_LOG" "$ARTIFACTS_DIR/" 2>/dev/null || true
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
    ip link del "$TAP" 2>/dev/null || true
    exit 1
  fi

  if ! kill -0 "$QEMU_PID" 2>/dev/null; then
    echo "ERROR: QEMU process exited unexpectedly"
    cp "$SERIAL_LOG" "$ARTIFACTS_DIR/" 2>/dev/null || true
    ip link del "$TAP" 2>/dev/null || true
    exit 1
  fi

  sleep "$poll_interval"
  elapsed=$((elapsed + poll_interval))
done

if [ "$elapsed" -ge "$INSTALL_TIMEOUT" ]; then
  echo "ERROR: Provision did not complete within ${INSTALL_TIMEOUT}s"
  cp "$SERIAL_LOG" "$ARTIFACTS_DIR/" 2>/dev/null || true
  kill "$QEMU_PID" 2>/dev/null || true
  wait "$QEMU_PID" 2>/dev/null || true
  ip link del "$TAP" 2>/dev/null || true
  exit 1
fi

# ---------------------------------------------------------------------------
# Wait for SSH
# ---------------------------------------------------------------------------
vm_ip=""
ssh_key_file="${CASE_WORK}/id_ed25519"
echo "Waiting for SSH (MAC: ${MAC})..."
elapsed=0
while [ "$elapsed" -lt "$SSH_TIMEOUT" ]; do
  current_ip=$(ip neigh show dev "$BRIDGE" \
    | grep -i "$MAC" \
    | grep -v FAILED \
    | awk '{print $1}' \
    | head -1 || true)
  if [ -n "$current_ip" ] && [ "$current_ip" != "$vm_ip" ]; then
    vm_ip="$current_ip"
    echo "  VM IP: ${vm_ip}"
  fi

  if [ -n "$vm_ip" ]; then
    if [ -f "$ssh_key_file" ]; then
      if ssh -i "$ssh_key_file" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=5 \
        -o BatchMode=yes \
        -o PreferredAuthentications=publickey \
        "${USERNAME}@${vm_ip}" "true" 2>/dev/null; then
        echo "SSH is available! (key auth)"
        break
      fi
    else
      if sshpass -p "$PASSWORD" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=5 \
        "${USERNAME}@${vm_ip}" "true" 2>/dev/null; then
        echo "SSH is available!"
        break
      fi
    fi
  fi
  sleep 10
  elapsed=$((elapsed + 10))
  echo "  [${elapsed}s] Waiting for SSH..."
done

if [ "$elapsed" -ge "$SSH_TIMEOUT" ]; then
  echo "ERROR: SSH did not become available within ${SSH_TIMEOUT}s (last IP: ${vm_ip:-none})"
  cp "$SERIAL_LOG" "$ARTIFACTS_DIR/" 2>/dev/null || true
  kill "$QEMU_PID" 2>/dev/null || true
  wait "$QEMU_PID" 2>/dev/null || true
  ip link del "$TAP" 2>/dev/null || true
  exit 1
fi

# ---------------------------------------------------------------------------
# Verify
# ---------------------------------------------------------------------------
echo "Running verify script..."
export EXPECTED_CODENAME="$CODENAME"
if ! "${SCRIPT_DIR}/verify.sh" "$vm_ip" "$USERNAME" "$PASSWORD" "$EXPECTED_HOSTNAME" "$EXPECTED_DOMAIN" "$CASE_WORK"; then
  echo "ERROR: Verification failed"
  cp "$SERIAL_LOG" "$ARTIFACTS_DIR/" 2>/dev/null || true
  kill "$QEMU_PID" 2>/dev/null || true
  wait "$QEMU_PID" 2>/dev/null || true
  ip link del "$TAP" 2>/dev/null || true
  exit 1
fi

# ---------------------------------------------------------------------------
# Power off VM
# ---------------------------------------------------------------------------
echo "Powering off VM..."
if [ -f "$ssh_key_file" ]; then
  ssh -i "$ssh_key_file" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=10 \
    -o BatchMode=yes \
    -o PreferredAuthentications=publickey \
    "${USERNAME}@${vm_ip}" \
    "echo '${PASSWORD}' | sudo -S poweroff" 2>/dev/null || true
else
  sshpass -p "$PASSWORD" ssh \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    "${USERNAME}@${vm_ip}" \
    "echo '${PASSWORD}' | sudo -S poweroff" 2>/dev/null || true
fi

elapsed=0
while [ "$elapsed" -lt 60 ] && kill -0 "$QEMU_PID" 2>/dev/null; do
  sleep 2
  elapsed=$((elapsed + 2))
done
if kill -0 "$QEMU_PID" 2>/dev/null; then
  kill -9 "$QEMU_PID" 2>/dev/null || true
fi

ip link del "$TAP" 2>/dev/null || true

echo ""
echo "================================================================"
echo "  PASS: ${DISTRO} ${VERSION} (${CODENAME})"
echo "================================================================"
