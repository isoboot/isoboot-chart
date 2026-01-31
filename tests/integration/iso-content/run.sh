#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ] || [ -z "${1:-}" ]; then
  echo "Usage: $0 <HOST_IP>" >&2
  exit 1
fi

HOST_IP=$1
DIR=$(cd "$(dirname "$0")" && pwd)
BOOT_MEDIAS="debian-12 debian-13"
GROUP_FAILURES=0

for BM in $BOOT_MEDIAS; do
  echo "=== static-content: ${BM} ==="
  echo ""

  # All BootMedia resources include firmware
  EXTRA_ARGS="--expect-firmware"

  set +e
  "$DIR/test.sh" "$HOST_IP" "$BM" $EXTRA_ARGS
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

for BM in $BOOT_MEDIAS; do
  results="/tmp/static-content-${BM}.results"
  if [ -f "$results" ]; then
    read -r passed tests < "$results"
    TOTAL_PASSED=$((TOTAL_PASSED + passed))
    TOTAL_TESTS=$((TOTAL_TESTS + tests))
  fi
done

echo "=== Summary ==="
for BM in $BOOT_MEDIAS; do
  results="/tmp/static-content-${BM}.results"
  if [ -f "$results" ]; then
    read -r passed tests < "$results"
    echo "  static-content/${BM}: ${passed}/${tests} passed"
  else
    echo "  static-content/${BM}: FAILED (no results)"
  fi
done
echo "  static-content: ${TOTAL_PASSED}/${TOTAL_TESTS} passed"

[ "$GROUP_FAILURES" -eq 0 ] || exit 1
