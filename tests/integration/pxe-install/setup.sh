#!/usr/bin/env bash
set -euo pipefail

# Sets up the shared test infrastructure: bridge network, dnsmasq, kind cluster,
# veth link, CRDs, and helm chart. Exports environment to $STATE_FILE for use
# by run-all.sh and teardown.sh.
#
# Must be run as root.

if [ "$(id -u)" -ne 0 ]; then
  echo "Error: this script must be run as root." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
WORK_DIR="/tmp/pxe-install-test"
STATE_FILE="${WORK_DIR}/state.env"

BRIDGE="br-test"

# ---------------------------------------------------------------------------
# Step 0 — KVM gate
# ---------------------------------------------------------------------------
echo "=== Step 0: KVM gate ==="
if [ ! -e /dev/kvm ] || [ ! -w /dev/kvm ]; then
  echo "KVM not available — skipping PXE install test"
  exit 0
fi
echo "KVM is available"

# ---------------------------------------------------------------------------
# Step 1 — Find unused subnet
# ---------------------------------------------------------------------------
echo "=== Step 1: Finding unused subnet ==="
SUBNET=""
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

BRIDGE_IP="${SUBNET}.1"
KIND_IP="${SUBNET}.10"
echo "Using subnet ${SUBNET}.0/24  (bridge=${BRIDGE_IP}  kind=${KIND_IP})"

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

# Load Go build cache into kind node
if [ -d /tmp/isoboot-cache ] && [ "$(ls -A /tmp/isoboot-cache 2>/dev/null)" ]; then
  echo "Loading Go build cache into kind node..."
  docker exec kind-control-plane mkdir -p /var/cache/isoboot/go
  cd /tmp/isoboot-cache && tar cf - . \
    | docker exec -i kind-control-plane tar xf - -C /var/cache/isoboot/go
  cd "$SCRIPT_DIR"
fi

# ---------------------------------------------------------------------------
# Step 4b — Mount ramdisks
# ---------------------------------------------------------------------------
echo "=== Step 4b: Mounting ramdisks ==="

# Squid cache ramdisk (3GB inside kind node)
docker exec kind-control-plane mkdir -p /var/cache/isoboot/squid
if ! docker exec kind-control-plane mount -t tmpfs -o size=3G tmpfs /var/cache/isoboot/squid; then
  echo "WARNING: Failed to mount squid cache ramdisk, continuing without it"
else
  echo "Squid cache ramdisk mounted (3GB)"
fi

# QCOW2 disk ramdisk (8GB on host — 4GB per parallel VM)
RAMDISK_DIR="${WORK_DIR}/ramdisk"
mkdir -p "$RAMDISK_DIR"
if ! mount -t tmpfs -o size=8G tmpfs "$RAMDISK_DIR"; then
  echo "WARNING: Failed to mount QCOW2 ramdisk, continuing without it"
  RAMDISK_DIR=""
else
  echo "QCOW2 ramdisk mounted at $RAMDISK_DIR (8GB)"
fi

# ---------------------------------------------------------------------------
# Step 5 — Connect kind container to bridge via veth
# ---------------------------------------------------------------------------
echo "=== Step 5: Connecting kind to $BRIDGE via veth ==="
KIND_CONTAINER="kind-control-plane"

ip link add veth-kind type veth peer name veth-kind-br
ip link set veth-kind-br master "$BRIDGE"
ip link set veth-kind-br up

KIND_PID=$(docker inspect -f '{{.State.Pid}}' "$KIND_CONTAINER")
ip link set veth-kind netns "$KIND_PID"

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
# Step 7 — Wait for pods + BootSources
# ---------------------------------------------------------------------------
echo "=== Step 7: Waiting for pods ==="
kubectl wait --for=condition=ready pod --all \
  -n isoboot --timeout=900s
echo "All pods ready"

echo "Waiting for BootSources..."
# Wait for all boot sources that exist
for bs in $(kubectl get bootsource -n isoboot -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
  echo "  Waiting for BootSource $bs..."
  kubectl wait --for=jsonpath='{.status.phase}'=Complete \
    "bootsource/$bs" -n isoboot --timeout=600s
  echo "  BootSource $bs is Complete"
done

# ---------------------------------------------------------------------------
# Write state file for run-all.sh and teardown.sh
# ---------------------------------------------------------------------------
cat > "$STATE_FILE" <<EOF
BRIDGE=${BRIDGE}
SUBNET=${SUBNET}
BRIDGE_IP=${BRIDGE_IP}
KIND_IP=${KIND_IP}
DNSMASQ_PID=${DNSMASQ_PID}
WORK_DIR=${WORK_DIR}
SCRIPT_DIR=${SCRIPT_DIR}
REPO_DIR=${REPO_DIR}
RAMDISK_DIR=${RAMDISK_DIR}
EOF

echo ""
echo "=== Setup complete ==="
echo "State written to $STATE_FILE"
