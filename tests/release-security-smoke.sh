#!/bin/bash

set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for installer in deploy-peta.sh deploy-peta-linux.sh; do
    work_dir="$(mktemp -d)"
    trap 'rm -rf "$work_dir"' EXIT

    (
        cd "$work_dir"
        PETA_AUTH_AUTOSTART=false
        source "$repo_dir/$installer"

        first="$(generate_password 32)"
        second="$(generate_password 32)"
        [[ ${#first} -eq 32 && ${#second} -eq 32 && "$first" != "$second" ]]

        generate_env_file 3 >/dev/null 2>&1
        mode="$(stat -f '%Lp' .env 2>/dev/null || stat -c '%a' .env)"
        [[ "$mode" == "600" ]]
        grep -Eq '^CONSOLE_JWT_SECRET=.{32}$' .env
        grep -Eq '^NEXTAUTH_SECRET=.{32}$' .env
    )

    rm -rf "$work_dir"
    trap - EXIT
done

grep -q 'RandomNumberGenerator.*Create' "$repo_dir/deploy-peta.ps1"
grep -q 'SetAccessRuleProtection' "$repo_dir/deploy-peta.ps1"
! grep -Eq 'md5sum|change-this-secret|Get-Random' \
    "$repo_dir/deploy-peta.sh" \
    "$repo_dir/deploy-peta-linux.sh" \
    "$repo_dir/deploy-peta.ps1"

echo "release security smoke passed"
