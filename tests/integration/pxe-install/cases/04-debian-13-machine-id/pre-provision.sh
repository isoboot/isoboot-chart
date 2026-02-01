#!/usr/bin/env bash
set -euo pipefail

# Generates a random machine-id using dbus-uuidgen and saves it to
# $CASE_WORK/expected-machine-id for later verification.
# Prints extra Provision spec fields to stdout.

CASE_WORK="$1"

if ! command -v dbus-uuidgen >/dev/null 2>&1; then
  echo "ERROR: dbus-uuidgen not found (install dbus package)" >&2
  exit 1
fi

MACHINE_ID_FILE="${CASE_WORK}/expected-machine-id"
rm -f "$MACHINE_ID_FILE"
dbus-uuidgen --ensure="$MACHINE_ID_FILE"
MACHINE_ID=$(dbus-uuidgen --get="$MACHINE_ID_FILE")

echo "  machineId: ${MACHINE_ID}"
