#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 2 ] || [ -z "${1:-}" ] || [ -z "${2:-}" ]; then
  echo "Usage: $0 <HOST_IP> <BOOTMEDIA> [--expect-firmware]" >&2
  exit 1
fi

HOST_IP=$1
BOOTMEDIA=$2
EXPECT_FIRMWARE=false
if [ "${3:-}" = "--expect-firmware" ]; then
  EXPECT_FIRMWARE=true
fi
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

# --- Setup: compute reference hashes from files on disk ---

echo "Setup: computing reference hashes from downloaded files"

# Kernel is always at top level
KERNEL_SHA=$(docker exec kind-control-plane \
  sha256sum "/opt/isoboot/files/${BOOTMEDIA}/linux" | awk '{print $1}')

echo "  kernel sha256: ${KERNEL_SHA}"

# Check for firmware (determines directory layout)
HAS_FIRMWARE=false
if docker exec kind-control-plane test -d "/opt/isoboot/files/${BOOTMEDIA}/no-firmware" 2>/dev/null; then
  HAS_FIRMWARE=true
  # With firmware: initrd in subdirectories
  INITRD_NO_FW_SHA=$(docker exec kind-control-plane \
    sha256sum "/opt/isoboot/files/${BOOTMEDIA}/no-firmware/initrd.gz" | awk '{print $1}')
  INITRD_WITH_FW_SHA=$(docker exec kind-control-plane \
    sha256sum "/opt/isoboot/files/${BOOTMEDIA}/with-firmware/initrd.gz" | awk '{print $1}')
  INITRD_NO_FW_SIZE=$(docker exec kind-control-plane \
    stat -c%s "/opt/isoboot/files/${BOOTMEDIA}/no-firmware/initrd.gz")
  INITRD_WITH_FW_SIZE=$(docker exec kind-control-plane \
    stat -c%s "/opt/isoboot/files/${BOOTMEDIA}/with-firmware/initrd.gz")
  echo "  initrd (no-firmware) sha256: ${INITRD_NO_FW_SHA}"
  echo "  initrd (with-firmware) sha256: ${INITRD_WITH_FW_SHA}"
  echo "  initrd (no-firmware) size: ${INITRD_NO_FW_SIZE}"
  echo "  initrd (with-firmware) size: ${INITRD_WITH_FW_SIZE}"
elif [ "$EXPECT_FIRMWARE" = "true" ]; then
  echo "FAIL: firmware expected but no-firmware/ directory not found for ${BOOTMEDIA}"
  exit 1
else
  # No firmware: initrd at top level
  INITRD_SHA=$(docker exec kind-control-plane \
    sha256sum "/opt/isoboot/files/${BOOTMEDIA}/initrd.gz" | awk '{print $1}')
  echo "  initrd sha256: ${INITRD_SHA}"
fi
echo ""

TMPDIR="/tmp/static-content-${BOOTMEDIA}"
mkdir -p "$TMPDIR"

# --- Tests ---

test_invalid_file_404() {
  local code
  code=$(curl -s -o /dev/null -w '%{http_code}' \
    "${BASE_URL}/static/${BOOTMEDIA}/nonexistent")
  [ "$code" = "404" ]
}

test_kernel() {
  curl -f -s -o "${TMPDIR}/kernel" \
    "${BASE_URL}/static/${BOOTMEDIA}/linux"
  local sha
  sha=$(sha256sum "${TMPDIR}/kernel" | awk '{print $1}')
  echo -n "(sha256=${sha}) "
  [ "$sha" = "$KERNEL_SHA" ]
}

test_initrd_no_firmware() {
  curl -f -s -o "${TMPDIR}/initrd-no-fw" \
    "${BASE_URL}/static/${BOOTMEDIA}/no-firmware/initrd.gz"
  local sha
  sha=$(sha256sum "${TMPDIR}/initrd-no-fw" | awk '{print $1}')
  echo -n "(sha256=${sha}) "
  [ "$sha" = "$INITRD_NO_FW_SHA" ]
}

test_initrd_with_firmware() {
  curl -f -s -o "${TMPDIR}/initrd-with-fw" \
    "${BASE_URL}/static/${BOOTMEDIA}/with-firmware/initrd.gz"
  local sha
  sha=$(sha256sum "${TMPDIR}/initrd-with-fw" | awk '{print $1}')
  echo -n "(sha256=${sha}) "
  [ "$sha" = "$INITRD_WITH_FW_SHA" ]
}

test_with_firmware_larger_than_no_firmware() {
  # with-firmware initrd must be larger than no-firmware initrd,
  # proving firmware was concatenated.
  [ "$INITRD_WITH_FW_SIZE" -gt "$INITRD_NO_FW_SIZE" ]
}

test_initrd_flat() {
  curl -f -s -o "${TMPDIR}/initrd" \
    "${BASE_URL}/static/${BOOTMEDIA}/initrd.gz"
  local sha
  sha=$(sha256sum "${TMPDIR}/initrd" | awk '{print $1}')
  echo -n "(sha256=${sha}) "
  [ "$sha" = "$INITRD_SHA" ]
}

run_test "invalid file returns 404" test_invalid_file_404
run_test "kernel matches downloaded file" test_kernel

if [ "$HAS_FIRMWARE" = "true" ]; then
  run_test "initrd (no-firmware) matches downloaded file" test_initrd_no_firmware
  run_test "initrd (with-firmware) matches downloaded file" test_initrd_with_firmware
  run_test "with-firmware initrd is larger than no-firmware" test_with_firmware_larger_than_no_firmware
else
  run_test "initrd matches downloaded file" test_initrd_flat
fi

PASSED=$((TESTS - FAILURES))
echo "static-content/${BOOTMEDIA}: ${PASSED}/${TESTS} passed"

# Write machine-readable results for the wrapper
echo "${PASSED} ${TESTS}" > "/tmp/static-content-${BOOTMEDIA}.results"

[ "$FAILURES" -eq 0 ] || exit 1
