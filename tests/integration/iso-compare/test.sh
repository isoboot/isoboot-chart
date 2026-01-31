#!/usr/bin/env bash
set -euo pipefail

# Compare files from direct download (debian-13) vs ISO extraction (debian-13-iso).
# Both reference the same upstream trixie netboot files and firmware, so the
# served kernel, initrd (no-firmware), and initrd (with-firmware) must be
# byte-identical.

if [ "$#" -lt 1 ] || [ -z "${1:-}" ]; then
  echo "Usage: $0 <HOST_IP>" >&2
  exit 1
fi

HOST_IP=$1
BASE_URL="http://${HOST_IP}:8080"
DIRECT="debian-13"
ISO="debian-13-iso"
TMPDIR="/tmp/iso-compare"
mkdir -p "$TMPDIR"
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

# Download a file and print its sha256
fetch_sha() {
  local url="$1" dest="$2"
  curl -f -s -o "$dest" "$url"
  sha256sum "$dest" | awk '{print $1}'
}

# --- Test 1: kernel ---

test_kernel_match() {
  local sha_direct sha_iso
  sha_direct=$(fetch_sha "${BASE_URL}/static/${DIRECT}/linux" "${TMPDIR}/kernel-direct")
  sha_iso=$(fetch_sha "${BASE_URL}/static/${ISO}/linux" "${TMPDIR}/kernel-iso")
  echo -n "(direct=${sha_direct:0:12}… iso=${sha_iso:0:12}…) "
  [ "$sha_direct" = "$sha_iso" ]
}

# --- Test 2: initrd (no-firmware) ---

test_initrd_no_firmware_match() {
  local sha_direct sha_iso
  sha_direct=$(fetch_sha "${BASE_URL}/static/${DIRECT}/no-firmware/initrd.gz" "${TMPDIR}/initrd-nf-direct")
  sha_iso=$(fetch_sha "${BASE_URL}/static/${ISO}/no-firmware/initrd.gz" "${TMPDIR}/initrd-nf-iso")
  echo -n "(direct=${sha_direct:0:12}… iso=${sha_iso:0:12}…) "
  [ "$sha_direct" = "$sha_iso" ]
}

# --- Test 3: initrd (with-firmware) ---

test_initrd_with_firmware_match() {
  local sha_direct sha_iso
  sha_direct=$(fetch_sha "${BASE_URL}/static/${DIRECT}/with-firmware/initrd.gz" "${TMPDIR}/initrd-wf-direct")
  sha_iso=$(fetch_sha "${BASE_URL}/static/${ISO}/with-firmware/initrd.gz" "${TMPDIR}/initrd-wf-iso")
  echo -n "(direct=${sha_direct:0:12}… iso=${sha_iso:0:12}…) "
  [ "$sha_direct" = "$sha_iso" ]
}

# --- Run tests ---

run_test "kernel: direct vs ISO extraction" test_kernel_match
run_test "initrd (no-firmware): direct vs ISO extraction" test_initrd_no_firmware_match
run_test "initrd (with-firmware): direct vs ISO extraction" test_initrd_with_firmware_match

PASSED=$((TESTS - FAILURES))
echo "iso-compare: ${PASSED}/${TESTS} passed"

[ "$FAILURES" -eq 0 ] || exit 1
