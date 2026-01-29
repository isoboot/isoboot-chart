#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 2 ] || [ -z "${1:-}" ] || [ -z "${2:-}" ]; then
  echo "Usage: $0 <HOST_IP> <DISKIMAGE>" >&2
  exit 1
fi

HOST_IP=$1
DISKIMAGE=$2
BASE_URL="http://${HOST_IP}:8080"
FAILURES=0
TESTS=0

run_test() {
  local name="$1"
  shift
  TESTS=$((TESTS + 1))
  echo -n "  TEST ${TESTS}: ${name} ... "
  if "$@"; then
    echo "PASS"
  else
    echo "FAIL"
    FAILURES=$((FAILURES + 1))
  fi
}

# --- Setup: mount ISO and compute reference hashes ---

echo "Setup: mounting ISO and computing reference hashes"

ISO_PATH=$(docker exec kind-control-plane \
  find "/opt/isoboot/iso/${DISKIMAGE}" -name 'mini.iso' -type f | head -1)
[ -n "$ISO_PATH" ] || {
  echo "mini.iso not found for ${DISKIMAGE}"
  docker exec kind-control-plane find /opt/isoboot/iso -type f
  exit 1
}

FW_PATH=$(docker exec kind-control-plane \
  find "/opt/isoboot/iso/${DISKIMAGE}" -name 'firmware.cpio.gz' -type f | head -1)
[ -n "$FW_PATH" ] || {
  echo "firmware.cpio.gz not found for ${DISKIMAGE}"
  docker exec kind-control-plane find /opt/isoboot/iso -type f
  exit 1
}

MOUNT_DIR="/tmp/iso-mount-${DISKIMAGE}"
docker exec kind-control-plane mkdir -p "$MOUNT_DIR"
docker exec kind-control-plane mount -o ro "$ISO_PATH" "$MOUNT_DIR"

ISO_KERNEL_SHA=$(docker exec kind-control-plane sha256sum "${MOUNT_DIR}/linux" | awk '{print $1}')
ISO_INITRD_SHA=$(docker exec kind-control-plane sha256sum "${MOUNT_DIR}/initrd.gz" | awk '{print $1}')
MERGED_INITRD_SHA=$(docker exec kind-control-plane \
  sh -c "cat ${MOUNT_DIR}/initrd.gz ${FW_PATH} | sha256sum" | awk '{print $1}')

docker exec kind-control-plane umount "$MOUNT_DIR"
docker exec kind-control-plane rmdir "$MOUNT_DIR"

echo "  ISO kernel sha256:    ${ISO_KERNEL_SHA}"
echo "  ISO initrd sha256:    ${ISO_INITRD_SHA}"
echo "  Merged initrd sha256: ${MERGED_INITRD_SHA}"
echo ""

# --- Tests ---

TMPDIR="/tmp/iso-content-${DISKIMAGE}"
mkdir -p "$TMPDIR"

test_invalid_file_404() {
  local code
  code=$(curl -s -o /dev/null -w '%{http_code}' \
    "${BASE_URL}/iso/content/${DISKIMAGE}-no-firmware/mini.iso/nonexistent")
  [ "$code" = "404" ]
}

test_kernel_no_firmware() {
  curl -f -s -o "${TMPDIR}/kernel-nfw" \
    "${BASE_URL}/iso/content/${DISKIMAGE}-no-firmware/mini.iso/linux"
  local sha
  sha=$(sha256sum "${TMPDIR}/kernel-nfw" | awk '{print $1}')
  echo -n "(sha256=${sha}) "
  [ "$sha" = "$ISO_KERNEL_SHA" ]
}

test_kernel_with_firmware() {
  curl -f -s -o "${TMPDIR}/kernel-wfw" \
    "${BASE_URL}/iso/content/${DISKIMAGE}-with-firmware/mini.iso/linux"
  local sha
  sha=$(sha256sum "${TMPDIR}/kernel-wfw" | awk '{print $1}')
  echo -n "(sha256=${sha}) "
  [ "$sha" = "$ISO_KERNEL_SHA" ]
}

test_initrd_no_firmware() {
  curl -f -s -o "${TMPDIR}/initrd-nfw" \
    "${BASE_URL}/iso/content/${DISKIMAGE}-no-firmware/mini.iso/initrd.gz"
  local sha
  sha=$(sha256sum "${TMPDIR}/initrd-nfw" | awk '{print $1}')
  echo -n "(sha256=${sha}) "
  [ "$sha" = "$ISO_INITRD_SHA" ]
}

test_initrd_with_firmware_differs() {
  curl -f -s -o "${TMPDIR}/initrd-wfw" \
    "${BASE_URL}/iso/content/${DISKIMAGE}-with-firmware/mini.iso/initrd.gz"
  local sha
  sha=$(sha256sum "${TMPDIR}/initrd-wfw" | awk '{print $1}')
  echo -n "(sha256=${sha}) "
  [ "$sha" != "$ISO_INITRD_SHA" ]
}

test_initrd_with_firmware_matches_merged() {
  curl -f -s -o "${TMPDIR}/initrd-wfw-merged" \
    "${BASE_URL}/iso/content/${DISKIMAGE}-with-firmware/mini.iso/initrd.gz"
  local sha
  sha=$(sha256sum "${TMPDIR}/initrd-wfw-merged" | awk '{print $1}')
  echo -n "(sha256=${sha} expected=${MERGED_INITRD_SHA}) "
  [ "$sha" = "$MERGED_INITRD_SHA" ]
}

run_test "invalid file returns 404" test_invalid_file_404
run_test "kernel no-firmware matches ISO" test_kernel_no_firmware
run_test "kernel with-firmware matches ISO" test_kernel_with_firmware
run_test "initrd no-firmware matches ISO" test_initrd_no_firmware
run_test "initrd with-firmware differs from raw ISO" test_initrd_with_firmware_differs
run_test "initrd with-firmware matches initrd+firmware.cpio.gz" test_initrd_with_firmware_matches_merged

PASSED=$((TESTS - FAILURES))
echo "iso-content/${DISKIMAGE}: ${PASSED}/${TESTS} passed"

# Write machine-readable results for the wrapper
echo "${PASSED} ${TESTS}" > "/tmp/iso-content-${DISKIMAGE}.results"

[ "$FAILURES" -eq 0 ] || exit 1
