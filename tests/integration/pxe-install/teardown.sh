#!/usr/bin/env bash
set -uo pipefail

# Tears down the shared test infrastructure created by setup.sh.
# Reads state from $STATE_FILE. Safe to run even if setup partially failed.
#
# Must be run as root.

WORK_DIR="/tmp/pxe-install-test"
STATE_FILE="${WORK_DIR}/state.env"

echo "=== Teardown ==="

# Source state if available
BRIDGE=""
SUBNET=""
DNSMASQ_PID=""
if [ -f "$STATE_FILE" ]; then
  # shellcheck disable=SC1090
  source "$STATE_FILE"
fi

# Save Go build cache from kind node
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^kind-control-plane$'; then
  if docker exec kind-control-plane test -d /var/cache/isoboot/go 2>/dev/null; then
    echo "Saving Go build cache from kind node..."
    sudo rm -rf /tmp/isoboot-cache
    mkdir -p /tmp/isoboot-cache
    docker exec kind-control-plane tar cf - -C /var/cache/isoboot/go . \
      | tar xf - -C /tmp/isoboot-cache
  fi
fi

# Delete kind cluster
if command -v kind &>/dev/null; then
  echo "Deleting kind cluster"
  kind delete cluster 2>/dev/null || true
fi

# Kill dnsmasq
if [ -n "$DNSMASQ_PID" ] && kill -0 "$DNSMASQ_PID" 2>/dev/null; then
  echo "Killing dnsmasq (PID $DNSMASQ_PID)"
  kill "$DNSMASQ_PID" 2>/dev/null || true
fi

# Unmount ramdisks
umount "${WORK_DIR}/ramdisk" 2>/dev/null || true

# Remove network resources
ip link del veth-kind-br 2>/dev/null || true
# Clean up any tap devices from parallel test runs
for tap in $(ip -o link show 2>/dev/null | grep -o 'tap-[0-9]*' || true); do
  ip link del "$tap" 2>/dev/null || true
done

if [ -n "$BRIDGE" ] && ip link show "$BRIDGE" &>/dev/null; then
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

echo "Teardown done"
