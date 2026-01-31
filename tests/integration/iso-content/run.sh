#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ] || [ -z "${1:-}" ]; then
  echo "Usage: $0 <HOST_IP>" >&2
  exit 1
fi

HOST_IP=$1
DIR=$(cd "$(dirname "$0")" && pwd)
DISK_IMAGES="debian-12 debian-13"
GROUP_FAILURES=0

for DISKIMAGE in $DISK_IMAGES; do
  echo "=== iso-content: ${DISKIMAGE} ==="
  echo ""

  set +e
  "$DIR/test.sh" "$HOST_IP" "$DISKIMAGE"
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

for DISKIMAGE in $DISK_IMAGES; do
  results="/tmp/iso-content-${DISKIMAGE}.results"
  if [ -f "$results" ]; then
    read -r passed tests < "$results"
    TOTAL_PASSED=$((TOTAL_PASSED + passed))
    TOTAL_TESTS=$((TOTAL_TESTS + tests))
  fi
done

echo "=== Summary ==="
for DISKIMAGE in $DISK_IMAGES; do
  results="/tmp/iso-content-${DISKIMAGE}.results"
  if [ -f "$results" ]; then
    read -r passed tests < "$results"
    echo "  iso-content/${DISKIMAGE}: ${passed}/${tests} passed"
  else
    echo "  iso-content/${DISKIMAGE}: FAILED (no results)"
  fi
done
echo "  iso-content: ${TOTAL_PASSED}/${TOTAL_TESTS} passed"

[ "$GROUP_FAILURES" -eq 0 ] || exit 1
