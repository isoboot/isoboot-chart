#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lib.sh"

parse_args "$@"
setup_password_ssh

verify_os_version
verify_hostname
verify_domain

exit "$FAIL"
