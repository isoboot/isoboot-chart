#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lib.sh"

parse_args "$@"

KNOWN_HOSTS="${CASE_WORK}/known_hosts"
build_known_hosts "$KNOWN_HOSTS"
verify_ssh_strict_host_keys "$KNOWN_HOSTS"

setup_password_ssh_strict "$KNOWN_HOSTS"

verify_os_version
verify_hostname
verify_domain
verify_host_key_hashes

exit "$FAIL"
