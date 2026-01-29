#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ] || [ -z "${1:-}" ]; then
  echo "Usage: $0 <HOST_IP>" >&2
  exit 1
fi

HOST_IP=$1
BASE_URL="http://${HOST_IP}:8080"
MAC="00-00-00-00-00-01"
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

# --- Test 1: boot.ipxe returns valid iPXE script ---

test_boot_ipxe() {
  local body code
  code=$(curl -s -o /tmp/boot-ipxe-body -w '%{http_code}' "${BASE_URL}/boot/boot.ipxe")
  body=$(cat /tmp/boot-ipxe-body)
  if [ "$code" != "200" ]; then
    echo -n "(HTTP ${code}) "
    return 1
  fi
  if ! echo "$body" | grep -q '#!ipxe'; then
    echo -n "(missing #!ipxe) "
    return 1
  fi
  if ! echo "$body" | grep -q 'conditional-boot?mac='; then
    echo -n "(missing conditional-boot chain) "
    return 1
  fi
}

# --- Test 2: conditional-boot 404 with no provision ---

test_conditional_boot_no_provision() {
  local code
  code=$(curl -s -o /dev/null -w '%{http_code}' \
    "${BASE_URL}/boot/conditional-boot?mac=${MAC}")
  if [ "$code" != "404" ]; then
    echo -n "(expected 404, got ${code}) "
    return 1
  fi
}

# --- Test 3: conditional-boot 200 with debian-13-no-firmware ---

test_conditional_boot_debian13() {
  # Create a Provision for debian-13-no-firmware
  kubectl apply -f - <<'EOF'
apiVersion: isoboot.io/v1alpha1
kind: Provision
metadata:
  name: test-boot-debian13
  namespace: isoboot
spec:
  machineRef: test-boot.lab
  bootTargetRef: debian-13-no-firmware
  responseTemplateRef: test-boot-rt
EOF

  # Wait for controller to reconcile to Pending
  kubectl wait --for=jsonpath='{.status.phase}'=Pending \
    provision/test-boot-debian13 -n isoboot --timeout=30s

  local body code
  code=$(curl -s -o /tmp/boot-conditional-body -w '%{http_code}' \
    "${BASE_URL}/boot/conditional-boot?mac=${MAC}")
  body=$(cat /tmp/boot-conditional-body)
  if [ "$code" != "200" ]; then
    echo -n "(expected 200, got ${code}) "
    return 1
  fi
  if ! echo "$body" | grep -q 'debian-13-no-firmware'; then
    echo -n "(missing debian-13-no-firmware in body) "
    return 1
  fi
}

# --- Test 4: conditional-boot 404 after done ---

test_conditional_boot_after_done() {
  # Mark the provision as complete via /boot/done
  local done_code
  done_code=$(curl -s -o /dev/null -w '%{http_code}' \
    "${BASE_URL}/boot/done?mac=${MAC}")
  if [ "$done_code" != "200" ]; then
    echo -n "(/boot/done returned ${done_code}, expected 200) "
    return 1
  fi

  # Now conditional-boot should 404 (no more Pending provisions)
  local code
  code=$(curl -s -o /dev/null -w '%{http_code}' \
    "${BASE_URL}/boot/conditional-boot?mac=${MAC}")
  if [ "$code" != "404" ]; then
    echo -n "(expected 404 after done, got ${code}) "
    return 1
  fi
}

# --- Test 5: conditional-boot 200 with debian-12-with-firmware ---

test_conditional_boot_debian12() {
  # Create a second Provision for debian-12-with-firmware
  kubectl apply -f - <<'EOF'
apiVersion: isoboot.io/v1alpha1
kind: Provision
metadata:
  name: test-boot-debian12
  namespace: isoboot
spec:
  machineRef: test-boot.lab
  bootTargetRef: debian-12-with-firmware
  responseTemplateRef: test-boot-rt
EOF

  # Wait for controller to reconcile to Pending
  kubectl wait --for=jsonpath='{.status.phase}'=Pending \
    provision/test-boot-debian12 -n isoboot --timeout=30s

  local body code
  code=$(curl -s -o /tmp/boot-conditional-body2 -w '%{http_code}' \
    "${BASE_URL}/boot/conditional-boot?mac=${MAC}")
  body=$(cat /tmp/boot-conditional-body2)
  if [ "$code" != "200" ]; then
    echo -n "(expected 200, got ${code}) "
    return 1
  fi
  if ! echo "$body" | grep -q 'debian-12-with-firmware'; then
    echo -n "(missing debian-12-with-firmware in body) "
    return 1
  fi
}

# --- Run tests ---

run_test "boot.ipxe returns valid iPXE script" test_boot_ipxe
run_test "conditional-boot 404 with no provision" test_conditional_boot_no_provision
run_test "conditional-boot 200 with debian-13-no-firmware" test_conditional_boot_debian13
run_test "conditional-boot 404 after done" test_conditional_boot_after_done
run_test "conditional-boot 200 with debian-12-with-firmware" test_conditional_boot_debian12

PASSED=$((TESTS - FAILURES))
echo "boot: ${PASSED}/${TESTS} passed"

# Write machine-readable results
echo "${PASSED} ${TESTS}" > /tmp/boot.results

[ "$FAILURES" -eq 0 ] || exit 1
