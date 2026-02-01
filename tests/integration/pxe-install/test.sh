#!/usr/bin/env bash
set -euo pipefail

# End-to-end PXE installation test for Debian 13 (trixie).
# Boots a QEMU VM via PXE on an isolated bridge network, installs Debian 13
# using isoboot running in a kind cluster, then verifies via SSH.
#
# Must be run as root (needs bridge/iptables/tap/qemu).

BRIDGE="br-test"
VM_MAC="52:54:00:12:34:56"
VM_NAME="pxe-test-vm"
PROVISION_NAME="pxe-test-debian13"
BOOT_TARGET="debian-13-no-firmware"
QEMU_RAM="1G"
QEMU_DISK_SIZE="20G"
INSTALL_TIMEOUT=2700  # 45 min
SSH_TIMEOUT=300       # 5 min

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
WORK_DIR="/tmp/pxe-install-test"

QEMU_PID=""
DNSMASQ_PID=""
SUBNET=""
TEST_PASSED=""

# ---------------------------------------------------------------------------
# Cleanup (runs on EXIT, even on failure)
# ---------------------------------------------------------------------------
cleanup() {
  echo ""
  echo "=== Cleanup ==="

  if [ -n "$QEMU_PID" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
    echo "Killing QEMU (PID $QEMU_PID)"
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
  fi

  if command -v kind &>/dev/null; then
    echo "Deleting kind cluster"
    kind delete cluster 2>/dev/null || true
  fi

  if [ -n "$DNSMASQ_PID" ] && kill -0 "$DNSMASQ_PID" 2>/dev/null; then
    echo "Killing dnsmasq (PID $DNSMASQ_PID)"
    kill "$DNSMASQ_PID" 2>/dev/null || true
  fi

  ip link del veth-kind-br 2>/dev/null || true
  ip link del tap-vm 2>/dev/null || true

  if ip link show "$BRIDGE" &>/dev/null; then
    echo "Removing bridge $BRIDGE"
    ip link set "$BRIDGE" down 2>/dev/null || true
    ip link del "$BRIDGE" 2>/dev/null || true
  fi

  if [ -n "$SUBNET" ]; then
    iptables -t nat -D POSTROUTING \
      -s "${SUBNET}.0/24" ! -o "$BRIDGE" -j MASQUERADE 2>/dev/null || true
    iptables -D FORWARD -i "$BRIDGE" -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -o "$BRIDGE" \
      -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
  fi

  # Preserve logs on failure for CI debug step
  if [ -n "$TEST_PASSED" ]; then
    rm -rf "$WORK_DIR"
  else
    echo "Preserving $WORK_DIR for debug (test did not pass)"
  fi

  echo "Cleanup done"
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Step 0 — KVM gate
# ---------------------------------------------------------------------------
echo "=== Step 0: KVM gate ==="
if [ ! -e /dev/kvm ] || [ ! -w /dev/kvm ]; then
  echo "KVM not available — skipping PXE install test"
  exit 0
fi
echo "KVM is available"

# Generate credentials early so we fail fast on any issues
PASSWORD=$(head -c 500 /dev/urandom | tr -dc a-z | cut -c1-16)
PASSWORD_HASH=$(openssl passwd -6 "$PASSWORD")
echo "Generated password for user 'isoboot' (hash: ${PASSWORD_HASH:0:20}...)"

# ---------------------------------------------------------------------------
# Step 1 — Find unused subnet
# ---------------------------------------------------------------------------
echo "=== Step 1: Finding unused subnet ==="
for i in $(seq 101 199); do
  if ! ip route show | grep -q "192.168.${i}\."; then
    SUBNET="192.168.${i}"
    break
  fi
done
if [ -z "$SUBNET" ]; then
  echo "ERROR: No unused subnet in 192.168.101-199 range"
  exit 1
fi

VM_IP="${SUBNET}.100"
BRIDGE_IP="${SUBNET}.1"
KIND_IP="${SUBNET}.10"
echo "Using subnet ${SUBNET}.0/24  (bridge=${BRIDGE_IP}  kind=${KIND_IP}  vm=${VM_IP})"

# ---------------------------------------------------------------------------
# Step 2 — Create bridge + NAT
# ---------------------------------------------------------------------------
echo "=== Step 2: Creating bridge and NAT ==="
ip link add "$BRIDGE" type bridge
ip addr add "${BRIDGE_IP}/24" dev "$BRIDGE"
ip link set "$BRIDGE" up

sysctl -q -w net.ipv4.ip_forward=1

iptables -t nat -A POSTROUTING \
  -s "${SUBNET}.0/24" ! -o "$BRIDGE" -j MASQUERADE
iptables -A FORWARD -i "$BRIDGE" -j ACCEPT
iptables -A FORWARD -o "$BRIDGE" \
  -m state --state RELATED,ESTABLISHED -j ACCEPT

echo "Bridge $BRIDGE up at $BRIDGE_IP"

# ---------------------------------------------------------------------------
# Step 3 — Start host dnsmasq (regular DHCP)
# ---------------------------------------------------------------------------
echo "=== Step 3: Starting host dnsmasq ==="
mkdir -p "$WORK_DIR"

dnsmasq \
  --conf-file= \
  --no-hosts \
  --interface="$BRIDGE" \
  --bind-interfaces \
  --dhcp-range="${SUBNET}.100,${SUBNET}.200,255.255.255.0,12h" \
  --dhcp-host="${VM_MAC},${VM_IP}" \
  --dhcp-option=3,"${BRIDGE_IP}" \
  --dhcp-option=6,8.8.8.8,8.8.4.4 \
  --log-queries \
  --log-dhcp \
  --log-facility="${WORK_DIR}/dnsmasq.log" \
  --pid-file="${WORK_DIR}/dnsmasq.pid"

DNSMASQ_PID=$(cat "${WORK_DIR}/dnsmasq.pid")
echo "dnsmasq started (PID $DNSMASQ_PID)"

# ---------------------------------------------------------------------------
# Step 4 — Create kind cluster
# ---------------------------------------------------------------------------
echo "=== Step 4: Creating kind cluster ==="
kind create cluster --wait 60s
echo "Kind cluster ready"

# ---------------------------------------------------------------------------
# Step 5 — Connect kind container to bridge via veth
# ---------------------------------------------------------------------------
echo "=== Step 5: Connecting kind to $BRIDGE via veth ==="
KIND_CONTAINER="kind-control-plane"

ip link add veth-kind type veth peer name veth-kind-br
ip link set veth-kind-br master "$BRIDGE"
ip link set veth-kind-br up

# Move veth-kind into the kind container's network namespace
KIND_PID=$(docker inspect -f '{{.State.Pid}}' "$KIND_CONTAINER")
ip link set veth-kind netns "$KIND_PID"

# Configure the interface inside the container
docker exec "$KIND_CONTAINER" ip addr add "${KIND_IP}/24" dev veth-kind
docker exec "$KIND_CONTAINER" ip link set veth-kind up

ISOBOOT_INTERFACE="veth-kind"
echo "Kind connected to $BRIDGE at $KIND_IP ($ISOBOOT_INTERFACE)"

# ---------------------------------------------------------------------------
# Step 6 — Install CRDs + helm chart
# ---------------------------------------------------------------------------
echo "=== Step 6: Installing CRDs and helm chart ==="
kubectl apply -f "${REPO_DIR}/crds/"

helm install isoboot "$REPO_DIR" -n isoboot --create-namespace \
  --set interface="$ISOBOOT_INTERFACE"

# ---------------------------------------------------------------------------
# Step 7 — Wait for pods + BootSource
# ---------------------------------------------------------------------------
echo "=== Step 7: Waiting for pods and BootSource ==="
kubectl wait --for=condition=ready pod --all \
  -n isoboot --timeout=900s
echo "All pods ready"

kubectl wait --for=jsonpath='{.status.phase}'=Complete \
  bootsource/debian-13 -n isoboot --timeout=600s
echo "BootSource debian-13 is Complete"

# ---------------------------------------------------------------------------
# Step 8 — Create ConfigMap
# ---------------------------------------------------------------------------
echo "=== Step 8: Creating ConfigMap ==="
kubectl create configmap pxe-test-config -n isoboot \
  --from-literal=language=en \
  --from-literal=country=US \
  --from-literal=keyboard=us \
  --from-literal=loginAsRoot=false \
  --from-literal=fullName=isoboot \
  --from-literal=username=isoboot \
  --from-literal=password="$PASSWORD_HASH" \
  --from-literal=timezone=UTC
echo "ConfigMap pxe-test-config created"

# ---------------------------------------------------------------------------
# Step 9 — Apply fixtures + create Provision
# ---------------------------------------------------------------------------
echo "=== Step 9: Applying fixtures ==="
kubectl apply -f "${SCRIPT_DIR}/fixtures.yaml"

kubectl apply -f - <<EOF
apiVersion: isoboot.io/v1alpha1
kind: Provision
metadata:
  name: ${PROVISION_NAME}
  namespace: isoboot
spec:
  machineRef: ${VM_NAME}
  bootTargetRef: ${BOOT_TARGET}
  responseTemplateRef: pxe-test-preseed
  configMaps:
    - pxe-test-config
EOF

kubectl wait --for=jsonpath='{.status.phase}'=Pending \
  provision/"${PROVISION_NAME}" -n isoboot --timeout=30s
echo "Provision is Pending"

# ---------------------------------------------------------------------------
# Step 10 — Record squid cache size (before)
# ---------------------------------------------------------------------------
echo "=== Step 10: Recording squid cache size (before) ==="
SQUID_POD=$(kubectl get pods -n isoboot \
  -l app.kubernetes.io/component=proxy \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

CACHE_BEFORE=0
if [ -n "$SQUID_POD" ]; then
  CACHE_BEFORE=$(kubectl exec -n isoboot "$SQUID_POD" -- \
    du -sm /var/spool/squid 2>/dev/null | awk '{print $1}' || echo "0")
fi
echo "Squid cache before: ${CACHE_BEFORE} MB"

# ---------------------------------------------------------------------------
# Step 11 — Create QEMU disk
# ---------------------------------------------------------------------------
echo "=== Step 11: Creating QEMU disk ==="
DISK="${WORK_DIR}/disk.qcow2"
qemu-img create -f qcow2 "$DISK" "$QEMU_DISK_SIZE"

# ---------------------------------------------------------------------------
# Step 12 — Launch QEMU VM
# ---------------------------------------------------------------------------
echo "=== Step 12: Launching QEMU VM ==="

# Create tap device on the bridge
ip tuntap add dev tap-vm mode tap
ip link set tap-vm master "$BRIDGE"
ip link set tap-vm up

# Locate OVMF firmware
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

# Copy OVMF vars (writable EFI variable store)
OVMF_VARS=""
for candidate in \
  /usr/share/OVMF/OVMF_VARS_4M.fd \
  /usr/share/OVMF/OVMF_VARS.fd \
  /usr/share/edk2/ovmf/OVMF_VARS.fd; do
  if [ -f "$candidate" ]; then
    cp "$candidate" "${WORK_DIR}/ovmf_vars.fd"
    OVMF_VARS="${WORK_DIR}/ovmf_vars.fd"
    break
  fi
done

echo "Using OVMF: $OVMF_CODE"

SERIAL_LOG="${WORK_DIR}/serial.log"

PFLASH_ARGS=( -drive "if=pflash,format=raw,readonly=on,file=${OVMF_CODE}" )
if [ -n "$OVMF_VARS" ]; then
  PFLASH_ARGS+=( -drive "if=pflash,format=raw,file=${OVMF_VARS}" )
fi

qemu-system-x86_64 \
  -enable-kvm \
  -m "$QEMU_RAM" \
  -cpu host \
  -smp 2 \
  -drive "file=${DISK},format=qcow2,if=virtio" \
  "${PFLASH_ARGS[@]}" \
  -netdev "tap,id=net0,ifname=tap-vm,script=no,downscript=no" \
  -device "virtio-net-pci,netdev=net0,mac=${VM_MAC}" \
  -serial "file:${SERIAL_LOG}" \
  -display none \
  -pidfile "${WORK_DIR}/qemu.pid" \
  -daemonize

sleep 2
QEMU_PID=$(cat "${WORK_DIR}/qemu.pid" 2>/dev/null || true)
if [ -z "$QEMU_PID" ] || ! kill -0 "$QEMU_PID" 2>/dev/null; then
  echo "ERROR: QEMU failed to start"
  cat "$SERIAL_LOG" 2>/dev/null || true
  exit 1
fi
echo "QEMU started (PID $QEMU_PID)"

# ---------------------------------------------------------------------------
# Step 13 — Poll Provision until Complete
# ---------------------------------------------------------------------------
echo "=== Step 13: Waiting for Provision to complete (timeout: ${INSTALL_TIMEOUT}s) ==="
ELAPSED=0
POLL_INTERVAL=30
while [ "$ELAPSED" -lt "$INSTALL_TIMEOUT" ]; do
  STATUS=$(kubectl get provision/"${PROVISION_NAME}" -n isoboot \
    -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
  echo "  [${ELAPSED}s] Provision status: ${STATUS}"

  if [ "$STATUS" = "Complete" ]; then
    echo "Provision is Complete!"
    break
  fi

  if [ "$STATUS" = "Failed" ] || [ "$STATUS" = "ConfigError" ]; then
    MSG=$(kubectl get provision/"${PROVISION_NAME}" -n isoboot \
      -o jsonpath='{.status.message}' 2>/dev/null || echo "")
    echo "ERROR: Provision ${STATUS}: ${MSG}"
    exit 1
  fi

  if ! kill -0 "$QEMU_PID" 2>/dev/null; then
    echo "ERROR: QEMU process exited unexpectedly"
    echo "Last serial output:"
    tail -50 "$SERIAL_LOG" 2>/dev/null || true
    exit 1
  fi

  sleep "$POLL_INTERVAL"
  ELAPSED=$((ELAPSED + POLL_INTERVAL))
done

if [ "$ELAPSED" -ge "$INSTALL_TIMEOUT" ]; then
  echo "ERROR: Provision did not complete within ${INSTALL_TIMEOUT}s"
  echo "Last serial output:"
  tail -50 "$SERIAL_LOG" 2>/dev/null || true
  exit 1
fi

# ---------------------------------------------------------------------------
# Step 14 — Wait for SSH
# ---------------------------------------------------------------------------
echo "=== Step 14: Waiting for SSH on ${VM_IP} ==="
ELAPSED=0
while [ "$ELAPSED" -lt "$SSH_TIMEOUT" ]; do
  if sshpass -p "$PASSWORD" ssh \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=5 \
    "isoboot@${VM_IP}" "true" 2>/dev/null; then
    echo "SSH is available!"
    break
  fi
  sleep 10
  ELAPSED=$((ELAPSED + 10))
  echo "  [${ELAPSED}s] Waiting for SSH..."
done

if [ "$ELAPSED" -ge "$SSH_TIMEOUT" ]; then
  echo "ERROR: SSH did not become available within ${SSH_TIMEOUT}s"
  exit 1
fi

# ---------------------------------------------------------------------------
# Step 15 — Verify installation
# ---------------------------------------------------------------------------
echo "=== Step 15: Verifying installation ==="
"${SCRIPT_DIR}/verify.sh" "$VM_IP" "isoboot" "$PASSWORD"
echo "PASS: Debian 13 (trixie) verified"

# ---------------------------------------------------------------------------
# Step 16 — Record squid cache size (after)
# ---------------------------------------------------------------------------
echo "=== Step 16: Recording squid cache size (after) ==="
CACHE_AFTER=0
if [ -n "$SQUID_POD" ]; then
  CACHE_AFTER=$(kubectl exec -n isoboot "$SQUID_POD" -- \
    du -sm /var/spool/squid 2>/dev/null | awk '{print $1}' || echo "0")
fi
echo "Squid cache after: ${CACHE_AFTER} MB"
echo "Squid cache delta: $((CACHE_AFTER - CACHE_BEFORE)) MB"

# ---------------------------------------------------------------------------
# Step 17 — Power off VM
# ---------------------------------------------------------------------------
echo "=== Step 17: Powering off VM ==="
sshpass -p "$PASSWORD" ssh \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  "isoboot@${VM_IP}" \
  "echo '${PASSWORD}' | sudo -S poweroff" 2>/dev/null || true

# Wait for QEMU to exit
ELAPSED=0
while [ "$ELAPSED" -lt 60 ] && kill -0 "$QEMU_PID" 2>/dev/null; do
  sleep 2
  ELAPSED=$((ELAPSED + 2))
done
if kill -0 "$QEMU_PID" 2>/dev/null; then
  echo "QEMU still running after 60s, force killing"
  kill -9 "$QEMU_PID" 2>/dev/null || true
fi
QEMU_PID=""

TEST_PASSED=1

echo ""
echo "=== PXE Install Test: PASSED ==="
