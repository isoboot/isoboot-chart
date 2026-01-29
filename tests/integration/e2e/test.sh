#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ] || [ -z "${1:-}" ]; then
  echo "Usage: $0 <HOST_IP>" >&2
  exit 1
fi

HOST_IP=$1
BASE_URL="http://${HOST_IP}:8080"
MAC="00-00-00-00-00-02"
WRONG_MAC="00-00-00-00-00-99"
PROVISION="test-e2e-debian12"
BOOT_TARGET="debian-12-no-firmware"
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

get_status() {
  kubectl get provision/"$PROVISION" -n isoboot -o jsonpath='{.status.phase}'
}

# --- Setup: mount ISO and compute reference hashes ---

echo "Setup: mounting ISO and computing reference hashes"

ISO_PATH=$(docker exec kind-control-plane \
  find "/opt/isoboot/iso/debian-12" -name 'mini.iso' -type f | head -1)
[ -n "$ISO_PATH" ] || {
  echo "mini.iso not found for debian-12"
  docker exec kind-control-plane find /opt/isoboot/iso -type f
  exit 1
}

MOUNT_DIR="/tmp/iso-mount-e2e"

cleanup_iso_mount() {
  docker exec kind-control-plane umount "$MOUNT_DIR" >/dev/null 2>&1 || true
  docker exec kind-control-plane rmdir "$MOUNT_DIR" >/dev/null 2>&1 || true
}
trap cleanup_iso_mount EXIT

docker exec kind-control-plane mkdir -p "$MOUNT_DIR"
docker exec kind-control-plane mount -o ro "$ISO_PATH" "$MOUNT_DIR"

ISO_KERNEL_SHA=$(docker exec kind-control-plane sha256sum "${MOUNT_DIR}/linux" | awk '{print $1}')
ISO_INITRD_SHA=$(docker exec kind-control-plane sha256sum "${MOUNT_DIR}/initrd.gz" | awk '{print $1}')

cleanup_iso_mount
trap - EXIT

echo "  ISO kernel sha256: ${ISO_KERNEL_SHA}"
echo "  ISO initrd sha256: ${ISO_INITRD_SHA}"
echo ""

TMPDIR="/tmp/e2e-boot"
mkdir -p "$TMPDIR"

# --- Test 1: conditional-boot 404 before any provision ---

test_initial_404() {
  local code
  code=$(curl -s -o /dev/null -w '%{http_code}' \
    "${BASE_URL}/boot/conditional-boot?mac=${MAC}")
  if [ "$code" != "404" ]; then
    echo -n "(expected 404, got ${code}) "
    return 1
  fi
}

# --- Test 2: create provision, verify Pending ---

test_create_provision_pending() {
  kubectl apply -f - <<EOF
apiVersion: isoboot.io/v1alpha1
kind: Provision
metadata:
  name: ${PROVISION}
  namespace: isoboot
spec:
  machineRef: test-e2e.lab
  bootTargetRef: ${BOOT_TARGET}
  responseTemplateRef: test-e2e-rt
EOF

  kubectl wait --for=jsonpath='{.status.phase}'=Pending \
    provision/"${PROVISION}" -n isoboot --timeout=30s
}

# --- Test 3: conditional-boot with wrong MAC, status still Pending ---

test_wrong_mac_404_still_pending() {
  local code
  code=$(curl -s -o /dev/null -w '%{http_code}' \
    "${BASE_URL}/boot/conditional-boot?mac=${WRONG_MAC}")
  if [ "$code" != "404" ]; then
    echo -n "(expected 404 for wrong MAC, got ${code}) "
    return 1
  fi
  local status
  status=$(get_status)
  if [ "$status" != "Pending" ]; then
    echo -n "(expected Pending, got ${status}) "
    return 1
  fi
}

# --- Test 4: conditional-boot with correct MAC, status InProgress ---

test_conditional_boot_200_in_progress() {
  local body code
  code=$(curl -s -o "${TMPDIR}/conditional-body" -w '%{http_code}' \
    "${BASE_URL}/boot/conditional-boot?mac=${MAC}")
  body=$(cat "${TMPDIR}/conditional-body")
  if [ "$code" != "200" ]; then
    echo -n "(expected 200, got ${code}) "
    return 1
  fi
  if ! echo "$body" | grep -q "${BOOT_TARGET}"; then
    echo -n "(missing ${BOOT_TARGET} in body) "
    return 1
  fi
  kubectl wait --for=jsonpath='{.status.phase}'=InProgress \
    provision/"${PROVISION}" -n isoboot --timeout=10s
}

# --- Test 5: GET kernel, verify SHA, status InProgress ---

test_kernel_in_progress() {
  curl -f -s -o "${TMPDIR}/kernel" \
    "${BASE_URL}/iso/content/${BOOT_TARGET}/mini.iso/linux"
  local sha
  sha=$(sha256sum "${TMPDIR}/kernel" | awk '{print $1}')
  if [ "$sha" != "$ISO_KERNEL_SHA" ]; then
    echo -n "(kernel sha256 mismatch: ${sha}) "
    return 1
  fi
  local status
  status=$(get_status)
  if [ "$status" != "InProgress" ]; then
    echo -n "(expected InProgress, got ${status}) "
    return 1
  fi
}

# --- Test 6: GET initrd, verify SHA, status InProgress ---

test_initrd_in_progress() {
  curl -f -s -o "${TMPDIR}/initrd" \
    "${BASE_URL}/iso/content/${BOOT_TARGET}/mini.iso/initrd.gz"
  local sha
  sha=$(sha256sum "${TMPDIR}/initrd" | awk '{print $1}')
  if [ "$sha" != "$ISO_INITRD_SHA" ]; then
    echo -n "(initrd sha256 mismatch: ${sha}) "
    return 1
  fi
  local status
  status=$(get_status)
  if [ "$status" != "InProgress" ]; then
    echo -n "(expected InProgress, got ${status}) "
    return 1
  fi
}

# --- Test 7: GET preseed, verify content, status InProgress ---

test_preseed_in_progress() {
  local body code
  code=$(curl -s -o "${TMPDIR}/preseed" -w '%{http_code}' \
    "${BASE_URL}/answer/${PROVISION}/preseed.cfg")
  body=$(cat "${TMPDIR}/preseed")
  if [ "$code" != "200" ]; then
    echo -n "(expected 200, got ${code}) "
    return 1
  fi
  if ! echo "$body" | grep -q "e2e-test-preseed"; then
    echo -n "(preseed content missing marker, got: ${body}) "
    return 1
  fi
  local status
  status=$(get_status)
  if [ "$status" != "InProgress" ]; then
    echo -n "(expected InProgress, got ${status}) "
    return 1
  fi
}

# --- Test 8: /boot/done, status Complete ---

test_done_complete() {
  local code
  code=$(curl -s -o /dev/null -w '%{http_code}' \
    "${BASE_URL}/boot/done?mac=${MAC}")
  if [ "$code" != "200" ]; then
    echo -n "(/boot/done returned ${code}, expected 200) "
    return 1
  fi
  kubectl wait --for=jsonpath='{.status.phase}'=Complete \
    provision/"${PROVISION}" -n isoboot --timeout=10s
}

# --- Test 9: conditional-boot 404 after done, status still Complete ---

test_after_done_404_still_complete() {
  local code
  code=$(curl -s -o /dev/null -w '%{http_code}' \
    "${BASE_URL}/boot/conditional-boot?mac=${MAC}")
  if [ "$code" != "404" ]; then
    echo -n "(expected 404, got ${code}) "
    return 1
  fi
  local status
  status=$(get_status)
  if [ "$status" != "Complete" ]; then
    echo -n "(expected Complete, got ${status}) "
    return 1
  fi
}

# --- Run tests ---

run_test "conditional-boot 404 before provision" test_initial_404
run_test "create provision and verify Pending" test_create_provision_pending
run_test "wrong MAC 404, status still Pending" test_wrong_mac_404_still_pending
run_test "conditional-boot 200 with ${BOOT_TARGET}, status InProgress" test_conditional_boot_200_in_progress
run_test "kernel matches ISO, status InProgress" test_kernel_in_progress
run_test "initrd matches ISO, status InProgress" test_initrd_in_progress
run_test "preseed content correct, status InProgress" test_preseed_in_progress
run_test "done returns 200, status Complete" test_done_complete
run_test "conditional-boot 404 after done, status Complete" test_after_done_404_still_complete

PASSED=$((TESTS - FAILURES))
echo "e2e: ${PASSED}/${TESTS} passed"

# Write machine-readable results
echo "${PASSED} ${TESTS}" > /tmp/e2e.results

[ "$FAILURES" -eq 0 ] || exit 1
