#!/usr/bin/env bash
set -euo pipefail

# Generates a random machine-id using dbus-uuidgen and saves it to
# $CASE_WORK/expected-machine-id for later verification.
# Prints extra Provision spec fields to stdout.

CASE_WORK="$1"

MACHINE_ID_FILE="${CASE_WORK}/expected-machine-id"
dbus-uuidgen --ensure="$MACHINE_ID_FILE"
MACHINE_ID=$(dbus-uuidgen --get="$MACHINE_ID_FILE")

echo "  machineId: ${MACHINE_ID}"
