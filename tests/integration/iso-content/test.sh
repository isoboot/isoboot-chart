#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 2 ] || [ -z "${1:-}" ] || [ -z "${2:-}" ]; then
  echo "Usage: $0 <HOST_IP> <BOOTTARGET>" >&2
  exit 1
fi

HOST_IP=$1
BOOTTARGET=$2
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

KERNEL_SHA=$(docker exec kind-control-plane \
  sha256sum "/opt/isoboot/files/${BOOTTARGET}/linux" | awk '{print $1}')
INITRD_SHA=$(docker exec kind-control-plane \
  sha256sum "/opt/isoboot/files/${BOOTTARGET}/initrd.gz" | awk '{print $1}')

echo "  kernel sha256: ${KERNEL_SHA}"
echo "  initrd sha256: ${INITRD_SHA}"

# Check if this is a with-firmware variant (has combined initrd.gz)
HAS_FIRMWARE=false
if docker exec kind-control-plane test -f "/opt/isoboot/files/${BOOTTARGET}/firmware.cpio.gz" 2>/dev/null; then
  HAS_FIRMWARE=true
  # For with-firmware variants, the served initrd.gz is the combined file (initrd + firmware)
  COMBINED_INITRD_SHA=$(docker exec kind-control-plane \
    sh -c "cat /opt/isoboot/files/${BOOTTARGET}/initrd.gz" | sha256sum | awk '{print $1}')
  echo "  combined initrd sha256: ${COMBINED_INITRD_SHA}"
fi
echo ""

TMPDIR="/tmp/static-content-${BOOTTARGET}"
mkdir -p "$TMPDIR"

# --- Tests ---

test_invalid_file_404() {
  local code
  code=$(curl -s -o /dev/null -w '%{http_code}' \
    "${BASE_URL}/static/${BOOTTARGET}/nonexistent")
  [ "$code" = "404" ]
}

test_kernel() {
  curl -f -s -o "${TMPDIR}/kernel" \
    "${BASE_URL}/static/${BOOTTARGET}/linux"
  local sha
  sha=$(sha256sum "${TMPDIR}/kernel" | awk '{print $1}')
  echo -n "(sha256=${sha}) "
  [ "$sha" = "$KERNEL_SHA" ]
}

test_initrd() {
  curl -f -s -o "${TMPDIR}/initrd" \
    "${BASE_URL}/static/${BOOTTARGET}/initrd.gz"
  local sha
  sha=$(sha256sum "${TMPDIR}/initrd" | awk '{print $1}')
  echo -n "(sha256=${sha}) "
  [ "$sha" = "$INITRD_SHA" ]
}

test_combined_initrd() {
  curl -f -s -o "${TMPDIR}/combined-initrd" \
    "${BASE_URL}/static/${BOOTTARGET}/initrd.gz"
  local sha
  sha=$(sha256sum "${TMPDIR}/combined-initrd" | awk '{print $1}')
  echo -n "(sha256=${sha}) "
  [ "$sha" = "$COMBINED_INITRD_SHA" ]
}

run_test "invalid file returns 404" test_invalid_file_404
run_test "kernel matches downloaded file" test_kernel
run_test "initrd matches downloaded file" test_initrd

if [ "$HAS_FIRMWARE" = "true" ]; then
  run_test "combined initrd matches on-disk file" test_combined_initrd
fi

PASSED=$((TESTS - FAILURES))
echo "static-content/${BOOTTARGET}: ${PASSED}/${TESTS} passed"

# Write machine-readable results for the wrapper
echo "${PASSED} ${TESTS}" > "/tmp/static-content-${BOOTTARGET}.results"

[ "$FAILURES" -eq 0 ] || exit 1
