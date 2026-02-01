#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lib.sh"

parse_args "$@"
setup_password_ssh

verify_ssh_password_auth
verify_os_version
verify_hostname
verify_domain
verify_ssh_key_auth

exit "$FAIL"
