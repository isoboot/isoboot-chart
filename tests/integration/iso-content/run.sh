#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ] || [ -z "${1:-}" ]; then
  echo "Usage: $0 <HOST_IP>" >&2
  exit 1
fi

HOST_IP=$1
DIR=$(cd "$(dirname "$0")" && pwd)
BOOT_TARGETS="debian-12-no-firmware debian-13-no-firmware debian-13-with-firmware"
GROUP_FAILURES=0

for BT in $BOOT_TARGETS; do
  echo "=== static-content: ${BT} ==="
  echo ""

  # Determine if this BootTarget should have firmware
  EXTRA_ARGS=""
  case "$BT" in
    *-with-firmware) EXTRA_ARGS="--expect-firmware" ;;
  esac

  set +e
  "$DIR/test.sh" "$HOST_IP" "$BT" $EXTRA_ARGS
  rc=$?
  set -e

  if [ "$rc" -ne 0 ]; then
    GROUP_FAILURES=$((GROUP_FAILURES + 1))
  fi
  echo ""
done

# --- Summary ---

TOTAL_PASSED=0
TOTAL_TESTS=0

for BT in $BOOT_TARGETS; do
  results="/tmp/static-content-${BT}.results"
  if [ -f "$results" ]; then
    read -r passed tests < "$results"
    TOTAL_PASSED=$((TOTAL_PASSED + passed))
    TOTAL_TESTS=$((TOTAL_TESTS + tests))
  fi
done

echo "=== Summary ==="
for BT in $BOOT_TARGETS; do
  results="/tmp/static-content-${BT}.results"
  if [ -f "$results" ]; then
    read -r passed tests < "$results"
    echo "  static-content/${BT}: ${passed}/${tests} passed"
  else
    echo "  static-content/${BT}: FAILED (no results)"
  fi
done
echo "  static-content: ${TOTAL_PASSED}/${TOTAL_TESTS} passed"

[ "$GROUP_FAILURES" -eq 0 ] || exit 1
