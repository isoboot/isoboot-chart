#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lib.sh"

parse_args "$@"

KNOWN_HOSTS="${CASE_WORK}/known_hosts"
build_known_hosts "$KNOWN_HOSTS"

verify_password_rejected "$KNOWN_HOSTS"
verify_ssh_key_auth "${CASE_WORK}/id_ed25519" "$KNOWN_HOSTS"

setup_key_ssh_strict "${CASE_WORK}/id_ed25519" "$KNOWN_HOSTS"

verify_os_version
verify_hostname
verify_domain
verify_machine_id
verify_host_key_hashes

exit "$FAIL"
