#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ] || [ -z "${1:-}" ]; then
  echo "Usage: $0 <HOST_IP>" >&2
  exit 1
fi

HOST_IP=$1
BASE_URL="http://${HOST_IP}:8080"
FAILURES=0
TESTS=0

run_test() {
  local name="$1"
  shift
  TESTS=$((TESTS + 1))
  echo -n "TEST ${TESTS}: ${name} ... "
  if "$@"; then
    echo "PASS"
  else
    echo "FAIL"
    FAILURES=$((FAILURES + 1))
  fi
}

# --- Setup: extract ISO and compute reference hashes ---

echo "=== Setup ==="

ISO_PATH=$(docker exec kind-control-plane \
  find /opt/isoboot/iso/debian-12 -name 'mini.iso' -type f | head -1)
[ -n "$ISO_PATH" ] || {
  echo "mini.iso not found"
  docker exec kind-control-plane find /opt/isoboot/iso -type f
  exit 1
}
echo "ISO: $ISO_PATH"

FW_PATH=$(docker exec kind-control-plane \
  find /opt/isoboot/iso/debian-12 -name 'firmware.cpio.gz' -type f | head -1)
[ -n "$FW_PATH" ] || {
  echo "firmware.cpio.gz not found"
  docker exec kind-control-plane find /opt/isoboot/iso -type f
  exit 1
}
echo "Firmware: $FW_PATH"

docker exec kind-control-plane apt-get update -qq
docker exec -e DEBIAN_FRONTEND=noninteractive kind-control-plane \
  apt-get install -y -qq libarchive-tools
docker exec kind-control-plane mkdir -p /tmp/iso-extract
docker exec kind-control-plane bsdtar -xf "$ISO_PATH" -C /tmp/iso-extract

ISO_KERNEL_SHA=$(docker exec kind-control-plane sha256sum /tmp/iso-extract/linux | awk '{print $1}')
ISO_INITRD_SHA=$(docker exec kind-control-plane sha256sum /tmp/iso-extract/initrd.gz | awk '{print $1}')
MERGED_INITRD_SHA=$(docker exec kind-control-plane \
  sh -c "cat /tmp/iso-extract/initrd.gz $FW_PATH | sha256sum" | awk '{print $1}')

echo "ISO kernel sha256:    $ISO_KERNEL_SHA"
echo "ISO initrd sha256:    $ISO_INITRD_SHA"
echo "Merged initrd sha256: $MERGED_INITRD_SHA"
echo ""

# --- Tests ---

echo "=== Tests ==="

test_invalid_file_404() {
  local code
  code=$(curl -s -o /dev/null -w '%{http_code}' \
    "${BASE_URL}/iso/content/debian-12-no-firmware/mini.iso/nonexistent")
  [ "$code" = "404" ]
}

test_kernel_no_firmware() {
  curl -f -s -o /tmp/http-kernel-nfw \
    "${BASE_URL}/iso/content/debian-12-no-firmware/mini.iso/linux"
  local sha
  sha=$(sha256sum /tmp/http-kernel-nfw | awk '{print $1}')
  echo -n "(sha256=$sha) "
  [ "$sha" = "$ISO_KERNEL_SHA" ]
}

test_kernel_with_firmware() {
  curl -f -s -o /tmp/http-kernel-wfw \
    "${BASE_URL}/iso/content/debian-12-with-firmware/mini.iso/linux"
  local sha
  sha=$(sha256sum /tmp/http-kernel-wfw | awk '{print $1}')
  echo -n "(sha256=$sha) "
  [ "$sha" = "$ISO_KERNEL_SHA" ]
}

test_initrd_no_firmware() {
  curl -f -s -o /tmp/http-initrd-nfw \
    "${BASE_URL}/iso/content/debian-12-no-firmware/mini.iso/initrd.gz"
  local sha
  sha=$(sha256sum /tmp/http-initrd-nfw | awk '{print $1}')
  echo -n "(sha256=$sha) "
  [ "$sha" = "$ISO_INITRD_SHA" ]
}

test_initrd_with_firmware_differs() {
  curl -f -s -o /tmp/http-initrd-wfw \
    "${BASE_URL}/iso/content/debian-12-with-firmware/mini.iso/initrd.gz"
  local sha
  sha=$(sha256sum /tmp/http-initrd-wfw | awk '{print $1}')
  echo -n "(sha256=$sha) "
  [ "$sha" != "$ISO_INITRD_SHA" ]
}

test_initrd_with_firmware_matches_merged() {
  curl -f -s -o /tmp/http-initrd-wfw \
    "${BASE_URL}/iso/content/debian-12-with-firmware/mini.iso/initrd.gz"
  local sha
  sha=$(sha256sum /tmp/http-initrd-wfw | awk '{print $1}')
  echo -n "(sha256=$sha expected=$MERGED_INITRD_SHA) "
  [ "$sha" = "$MERGED_INITRD_SHA" ]
}

run_test "invalid file returns 404" test_invalid_file_404
run_test "kernel no-firmware matches ISO" test_kernel_no_firmware
run_test "kernel with-firmware matches ISO" test_kernel_with_firmware
run_test "initrd no-firmware matches ISO" test_initrd_no_firmware
run_test "initrd with-firmware differs from raw ISO" test_initrd_with_firmware_differs
run_test "initrd with-firmware matches initrd+firmware.cpio.gz" test_initrd_with_firmware_matches_merged

echo ""
echo "Results: $((TESTS - FAILURES))/${TESTS} passed"
[ "$FAILURES" -eq 0 ] || exit 1
