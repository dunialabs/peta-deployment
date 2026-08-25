#!/bin/bash

set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for installer in deploy-peta.sh deploy-peta-linux.sh; do
    PETA_VERSION=0.0.0 PETA_AUTH_VERSION= bash -c 'source "$1"; [[ "$PETA_AUTH_VERSION" == "1.3.0" ]]' _ "$repo_dir/$installer"

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

        PETA_AUTH_AUTOSTART=false
        generate_env_file 2 >/dev/null 2>&1
        generate_docker_compose 2 >/dev/null
        docker compose --env-file .env config --format json > compose-false.json
        node -e 'const compose = require("./compose-false.json"); if (compose.services["peta-auth"] || compose.secrets) process.exit(1)'

        PETA_AUTH_AUTOSTART=true
        ! require_peta_auth_runtime_secrets >/dev/null 2>&1
        mkdir peta-deployment
        ! has_existing_deployment peta-deployment
        is_safe_new_deployment_directory peta-deployment
        touch peta-deployment/operator-notes.txt
        ! is_safe_new_deployment_directory peta-deployment
        [[ -f peta-deployment/operator-notes.txt ]]
        mv peta-deployment/operator-notes.txt peta-deployment/operator-notes.saved
        ! is_safe_new_deployment_directory peta-deployment
        mv peta-deployment/operator-notes.saved operator-notes.saved
        mkdir secrets
        dd if=/dev/zero of=secrets/peta_auth_master_key bs=32 count=1 status=none
        dd if=/dev/zero of=secrets/peta_auth_client_secrets.json bs=2 count=1 status=none
        chmod 600 secrets/peta_auth_master_key secrets/peta_auth_client_secrets.json
        chmod 777 secrets
        ! require_peta_auth_runtime_secrets >/dev/null 2>&1
        chmod 700 secrets
        require_peta_auth_runtime_secrets
        mv secrets peta-deployment
        is_safe_new_deployment_directory peta-deployment
        chmod 777 peta-deployment/secrets
        ! is_safe_new_deployment_directory peta-deployment
        chmod 700 peta-deployment/secrets
        is_safe_new_deployment_directory peta-deployment
        touch peta-deployment/secrets/operator-notes.txt
        ! is_safe_new_deployment_directory peta-deployment
        [[ -f peta-deployment/secrets/operator-notes.txt ]]
        mv peta-deployment/secrets/operator-notes.txt operator-notes-in-secrets.saved
        mv peta-deployment/secrets secrets
        dd if=/dev/zero of=secrets/peta_auth_master_key bs=31 count=1 status=none
        ! require_peta_auth_runtime_secrets >/dev/null 2>&1
        dd if=/dev/zero of=secrets/peta_auth_master_key bs=32 count=1 status=none
        chmod 640 secrets/peta_auth_master_key
        ! require_peta_auth_runtime_secrets >/dev/null 2>&1
        chmod 600 secrets/peta_auth_master_key
        mv secrets/peta_auth_master_key secrets/peta_auth_master_key.actual
        ln -s peta_auth_master_key.actual secrets/peta_auth_master_key
        ! require_peta_auth_runtime_secrets >/dev/null 2>&1
        rm secrets/peta_auth_master_key
        mv secrets/peta_auth_master_key.actual secrets/peta_auth_master_key
        mv secrets/peta_auth_client_secrets.json secrets/peta_auth_client_secrets.json.actual
        ln -s peta_auth_client_secrets.json.actual secrets/peta_auth_client_secrets.json
        ! require_peta_auth_runtime_secrets >/dev/null 2>&1
        rm secrets/peta_auth_client_secrets.json
        mv secrets/peta_auth_client_secrets.json.actual secrets/peta_auth_client_secrets.json
        generate_env_file 2 >/dev/null 2>&1
        ! grep -Eq '^PETA_AUTH_(MASTER_KEY_FILE|CLIENT_SECRETS_FILE)=' .env
        generate_docker_compose 2 >/dev/null
        grep -q 'PETA_AUTH_MASTER_KEY_FILE: /run/secrets/peta_auth_master_key' docker-compose.yml
        grep -q 'PETA_AUTH_CLIENT_SECRETS_FILE: /run/secrets/peta_auth_client_secrets_json' docker-compose.yml
        grep -q 'GET /healthz HTTP/1.1' docker-compose.yml
        docker compose --env-file .env config --format json > compose-true.json
        node -e 'const compose = require("./compose-true.json"); const names = Object.keys(compose.secrets || {}).sort(); if (names.join(",") !== "peta_auth_client_secrets_json,peta_auth_master_key") process.exit(1); for (const [name, service] of Object.entries(compose.services)) { if (name !== "peta-auth" && service.secrets) process.exit(1) }; const auth = compose.services["peta-auth"]; if (!auth || auth.secrets.length !== 2) process.exit(1)'

        PETA_VERSION=1.2.9
        PETA_AUTH_VERSION=1.3.0
        generate_env_file 1 >/dev/null 2>&1
        grep -qx 'PETA_VERSION=1.2.9' .env
        grep -qx 'PETA_AUTH_VERSION=1.3.0' .env
        generate_docker_compose 1 >/dev/null
        docker compose --env-file .env config --format json > compose-rollback.json
        node -e 'const compose = require("./compose-rollback.json"); const expected = { "peta-core": "petaio/peta-core:1.2.9", "peta-console": "petaio/peta-console:1.2.9", "peta-auth": "petaio/peta-auth:1.3.0" }; for (const [name, image] of Object.entries(expected)) if (compose.services[name]?.image !== image) process.exit(1)'
    )

    rm -rf "$work_dir"
    trap - EXIT

    gnu_stat_work_dir="$(mktemp -d)"
    trap 'rm -rf "$gnu_stat_work_dir"' EXIT
    (
        cd "$gnu_stat_work_dir"
        source "$repo_dir/$installer"
        mkdir gnu-stat-secrets
        dd if=/dev/zero of=gnu-stat-secrets/peta_auth_master_key bs=32 count=1 status=none
        printf '{}' > gnu-stat-secrets/peta_auth_client_secrets.json
        chmod 700 gnu-stat-secrets
        chmod 600 gnu-stat-secrets/peta_auth_master_key gnu-stat-secrets/peta_auth_client_secrets.json
        stat() {
            case "$1" in
                -c)
                    case "$2" in
                        '%a') case "$3" in *secrets) printf '700\n' ;; *) printf '600\n' ;; esac ;;
                        '%u') id -u ;;
                    esac
                    ;;
                -f) printf 'GNU stat filesystem report\n' ;;
                *) command stat "$@" ;;
            esac
        }
        has_valid_peta_auth_runtime_secrets gnu-stat-secrets
    )
    rm -rf "$gnu_stat_work_dir"
    trap - EXIT

    main_work_dir="$(mktemp -d)"
    trap 'rm -rf "$main_work_dir"' EXIT
    mkdir "$main_work_dir/bin" "$main_work_dir/peta-deployment"
    ln -s /usr/bin/true "$main_work_dir/bin/docker"
    touch "$main_work_dir/peta-deployment/operator-notes.txt"
    ! (
        cd "$main_work_dir"
        PATH="$main_work_dir/bin:$PATH" DEPLOY_DIR="$main_work_dir/peta-deployment" bash "$repo_dir/$installer" > deployment-rejection.log 2>&1
    )
    grep -q 'Refusing to use' "$main_work_dir/deployment-rejection.log"
    [[ -f "$main_work_dir/peta-deployment/operator-notes.txt" ]]
    [[ ! -e "$main_work_dir/peta-deployment/.env" ]]
    [[ ! -e "$main_work_dir/peta-deployment/docker-compose.yml" ]]

    literal_rollback_dir="$main_work_dir/deploy rollback [literal]*"
    mkdir -p "$literal_rollback_dir"
    touch "$literal_rollback_dir/.env"
    printf '2\n' | (
        cd "$main_work_dir"
        PATH="$main_work_dir/bin:$PATH" DEPLOY_DIR="$literal_rollback_dir" bash "$repo_dir/$installer" > literal-rollback.log 2>&1
    )
    printf -v literal_rollback_command 'rm -rf -- %q' "$literal_rollback_dir"
    grep -Fq "$literal_rollback_command" "$main_work_dir/literal-rollback.log"

    literal_deploy_dir="$main_work_dir/deploy dir [literal]*"
    ln -s /usr/bin/true "$main_work_dir/bin/curl"
    ln -s /usr/bin/true "$main_work_dir/bin/sleep"
    printf '2\nn\n' | (
        cd "$main_work_dir"
        PATH="$main_work_dir/bin:$PATH" DEPLOY_DIR="$literal_deploy_dir" bash "$repo_dir/$installer" > literal-deployment.log 2>&1
    )
    grep -q 'Deployment completed' "$main_work_dir/literal-deployment.log"
    [[ -d "$literal_deploy_dir/cloudflared" ]]
    [[ -f "$literal_deploy_dir/.env" ]]
    [[ -f "$literal_deploy_dir/docker-compose.yml" ]]

    mkdir "$main_work_dir/volume-bin"
    printf '%s\n' '#!/bin/bash' 'if [ "$1" = volume ] && [ "$2" = ls ]; then printf "%s\\n" postgres_peta_core; fi' 'exit 0' > "$main_work_dir/volume-bin/docker"
    chmod +x "$main_work_dir/volume-bin/docker"
    literal_volume_dir="$main_work_dir/existing db [literal]*"
    printf '2\nn\n' | (
        cd "$main_work_dir"
        PATH="$main_work_dir/volume-bin:$PATH" DEPLOY_DIR="$literal_volume_dir" bash "$repo_dir/$installer" > literal-volume-recovery.log 2>&1
    )
    printf -v literal_volume_removal 'rm -rf -- %q' "$literal_volume_dir"
    printf -v literal_volume_editor 'vi -- %q' "$literal_volume_dir/.env"
    printf -v literal_volume_start 'cd -- %q' "$literal_volume_dir"
    grep -Fq "$literal_volume_removal" "$main_work_dir/literal-volume-recovery.log"
    grep -Fq "$literal_volume_editor" "$main_work_dir/literal-volume-recovery.log"
    grep -Fq "$literal_volume_start" "$main_work_dir/literal-volume-recovery.log"

    rm -rf "$main_work_dir"
    trap - EXIT
done

node -e 'const raw = Buffer.from([0xff]).toString("base64").slice(0, 2); const parsed = new URL("postgresql://peta:" + raw + "@postgres-core:5432/peta_core_postgres"); if (parsed.host === "postgres-core:5432") process.exit(1)'
awk '/function Generate-Password/,/^}/' "$repo_dir/deploy-peta.ps1" | grep -Fq "ToBase64String(\$bytes).Replace('+', '-').Replace('/', '_').TrimEnd('=')"

if command -v pwsh >/dev/null 2>&1; then
    work_dir="$(mktemp -d)"
    trap 'rm -rf "$work_dir"' EXIT

    PS_SCRIPT="$repo_dir/deploy-peta.ps1" PETA_DEPLOY_TEST_DIR="$work_dir/peta-deployment" pwsh -NoProfile -NonInteractive -Command '
        $tokens = $null
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($env:PS_SCRIPT, [ref]$tokens, [ref]$errors)
        if ($errors.Count -ne 0) { throw "deploy-peta.ps1 must parse without errors" }
        . $env:PS_SCRIPT
        1..100 | ForEach-Object {
            $password = Generate-Password -Length 24
            if ($password.Length -ne 24 -or $password -notmatch "^[A-Za-z0-9_-]+$") { throw "generated database password is not URL-safe" }
        }
        $dir = $env:PETA_DEPLOY_TEST_DIR
        $literalDir = [System.IO.Path]::Combine((Split-Path -LiteralPath $dir -Parent), "peta deploy [literal]*")
        [System.IO.Directory]::CreateDirectory($literalDir) | Out-Null
        Set-Content -LiteralPath ([System.IO.Path]::Combine($literalDir, ".env")) -Value "literal deployment" -NoNewline
        if (-not (Test-ExistingDeployment -Path $literalDir)) { throw "literal deployment path was not detected" }
        Push-Location -LiteralPath $literalDir
        if ((Get-Location).Path -ne $literalDir) { throw "literal deployment path was not entered" }
        Pop-Location
        New-Item -ItemType Directory -Path $dir | Out-Null
        if (-not (Test-SafeNewDeploymentDirectory -Path $dir)) { throw "empty deployment directory was rejected" }
        Set-Content -LiteralPath (Join-Path $dir "operator-notes.txt") -Value "preserve me" -NoNewline
        if (Test-SafeNewDeploymentDirectory -Path $dir) { throw "operator file was accepted" }
        if (-not (Test-Path -LiteralPath (Join-Path $dir "operator-notes.txt") -PathType Leaf)) { throw "operator file was modified" }
        Remove-Item -LiteralPath (Join-Path $dir "operator-notes.txt")
        $secrets = Join-Path $dir "secrets"
        New-Item -ItemType Directory -Path $secrets | Out-Null
        [System.IO.File]::WriteAllBytes((Join-Path $secrets "peta_auth_master_key"), [byte[]]::new(32))
        [System.IO.File]::WriteAllText((Join-Path $secrets "peta_auth_client_secrets.json"), "{}")
        if (Test-ValidPetaAuthRuntimeSecrets -SecretsDir $secrets) { throw "unprotected secret ACL was accepted" }
        Get-ChildItem -LiteralPath $secrets -File | ForEach-Object { Set-CurrentUserOnlyAcl -Path $_.FullName }
        if (Test-ValidPetaAuthRuntimeSecrets -SecretsDir $secrets) { throw "unprotected secrets directory ACL was accepted" }
        Set-CurrentUserOnlyAcl -Path $secrets
        if (-not (Test-SafeNewDeploymentDirectory -Path $dir)) { throw "validated secrets directory was rejected" }
        $directoryAcl = Get-Acl -LiteralPath $secrets
        $directoryAcl.SetAccessRuleProtection($false, $true)
        Set-Acl -LiteralPath $secrets -AclObject $directoryAcl
        if (Test-SafeNewDeploymentDirectory -Path $dir) { throw "broad secrets directory ACL was accepted" }
        Set-CurrentUserOnlyAcl -Path $secrets
        $masterKey = Join-Path $secrets "peta_auth_master_key"
        $acl = Get-Acl -LiteralPath $masterKey
        $usersSid = [System.Security.Principal.SecurityIdentifier]::new([System.Security.Principal.WellKnownSidType]::BuiltinUsersSid, $null)
        $acl.AddAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new($usersSid, [System.Security.AccessControl.FileSystemRights]::Read, [System.Security.AccessControl.AccessControlType]::Allow))
        Set-Acl -LiteralPath $masterKey -AclObject $acl
        if (Test-ValidPetaAuthRuntimeSecrets -SecretsDir $secrets) { throw "other-user allow ACL was accepted" }
        Set-CurrentUserOnlyAcl -Path $masterKey
        Set-Content -LiteralPath (Join-Path $secrets "operator-notes.txt") -Value "preserve me" -NoNewline
        if (Test-SafeNewDeploymentDirectory -Path $dir) { throw "extra secrets file was accepted" }
        if (-not (Test-Path -LiteralPath (Join-Path $secrets "operator-notes.txt") -PathType Leaf)) { throw "extra secrets file was modified" }
        Remove-Item -LiteralPath (Join-Path $secrets "operator-notes.txt")
        Push-Location $dir
        try {
            $script:PETA_AUTH_AUTOSTART = "true"
            Require-PetaAuthRuntimeSecrets
            $PETA_VERSION = "1.2.9"
            $PETA_AUTH_VERSION = "1.3.0"
            New-EnvFile -DeployMode "1"
            New-DockerCompose -DeployMode "1"
            if (-not (Select-String -LiteralPath "docker-compose.yml" -SimpleMatch "PETA_AUTH_MASTER_KEY_FILE: /run/secrets/peta_auth_master_key" -Quiet)) { throw "Auth secret mount was not generated" }
            if (-not (Select-String -LiteralPath ".env" -SimpleMatch "PETA_AUTH_VERSION=1.3.0" -Quiet)) { throw "Auth version was not persisted" }
            $compose = Get-Content -LiteralPath "docker-compose.yml" -Raw
            if ($compose -notmatch 'petaio/peta-core:\$\{PETA_VERSION\}' -or $compose -notmatch 'petaio/peta-console:\$\{PETA_VERSION\}' -or $compose -notmatch 'petaio/peta-auth:\$\{PETA_AUTH_VERSION\}') { throw "service version override was not generated" }

            $script:PETA_AUTH_AUTOSTART = "false"
            New-EnvFile -DeployMode "1"
            New-DockerCompose -DeployMode "1"
            $compose = Get-Content -LiteralPath "docker-compose.yml" -Raw
            if ($compose -notmatch "(?m)^services:\r?\n" -or $compose -notmatch "(?m)^volumes:\r?\n") { throw "Auth-disabled Compose top-level sections were concatenated" }
            if ($compose -match "(?m)^\s{2}peta-auth:" -or $compose -match "(?m)^secrets:\r?$") { throw "Auth-disabled Compose retained Auth services or secrets" }
            if (Get-Command docker -ErrorAction SilentlyContinue) {
                & docker compose config --quiet
                if ($LASTEXITCODE -ne 0) { throw "Auth-disabled Compose config was rejected" }
            }
        }
        finally {
            Pop-Location
        }
    '

    rm -rf "$work_dir"
    trap - EXIT
else
    grep -q 'RandomNumberGenerator.*Create' "$repo_dir/deploy-peta.ps1"
    ! grep -q '\$DEPLOY_DIR:' "$repo_dir/deploy-peta.ps1"
    grep -q 'SetAccessRuleProtection' "$repo_dir/deploy-peta.ps1"
    grep -q 'function Test-CurrentUserOnlyAcl' "$repo_dir/deploy-peta.ps1"
    awk '/function Test-CurrentUserOnlyAcl/,/^}/' "$repo_dir/deploy-peta.ps1" | grep -q 'GetOwner'
    awk '/function Test-CurrentUserOnlyAcl/,/^}/' "$repo_dir/deploy-peta.ps1" | grep -q 'AreAccessRulesProtected'
    awk '/function Test-CurrentUserOnlyAcl/,/^}/' "$repo_dir/deploy-peta.ps1" | grep -q 'AccessControlType]::Allow'
    awk '/function Test-ValidPetaAuthRuntimeSecrets/,/^}/' "$repo_dir/deploy-peta.ps1" | grep -q 'Test-CurrentUserOnlyAcl -Path \$path'
    awk '/function Test-ValidPetaAuthRuntimeSecrets/,/^}/' "$repo_dir/deploy-peta.ps1" | grep -q 'Test-CurrentUserOnlyAcl -Path \$SecretsDir'
    awk '/function Require-PetaAuthRuntimeSecrets/,/^}/' "$repo_dir/deploy-peta.ps1" | grep -q '@(\$secretsDir, \$masterKey, \$clientSecrets)'
    grep -q 'Require-PetaAuthRuntimeSecrets' "$repo_dir/deploy-peta.ps1"
    grep -q 'function Test-SafeNewDeploymentDirectory' "$repo_dir/deploy-peta.ps1"
    grep -q 'function Test-ValidPetaAuthRuntimeSecrets' "$repo_dir/deploy-peta.ps1"
    grep -q 'Refusing to use .*validated Peta Auth secrets' "$repo_dir/deploy-peta.ps1"
    grep -q 'peta_auth_client_secrets_json' "$repo_dir/deploy-peta.ps1"
    grep -q 'GET /healthz HTTP/1.1' "$repo_dir/deploy-peta.ps1"
    grep -q '\$PETA_AUTH_VERSION = if (\$env:PETA_AUTH_VERSION) { \$env:PETA_AUTH_VERSION } else { "1.3.0" }' "$repo_dir/deploy-peta.ps1"
    grep -q 'image: petaio/peta-auth:${PETA_AUTH_VERSION}' "$repo_dir/deploy-peta.ps1"
    grep -q 'Push-Location -LiteralPath \$DEPLOY_DIR' "$repo_dir/deploy-peta.ps1"
    grep -q '\[System.IO.Directory\]::CreateDirectory(\$DEPLOY_DIR)' "$repo_dir/deploy-peta.ps1"
    grep -q 'Remove-Item -LiteralPath \$literalDeployDir -Recurse -Force' "$repo_dir/deploy-peta.ps1"
    grep -q 'Remove-Item -LiteralPath \$literalCurrentDir -Recurse -Force' "$repo_dir/deploy-peta.ps1"
    awk '/function Show-DeploymentInfo/,/^}/' "$repo_dir/deploy-peta.ps1" | grep -q 'Set-Location -LiteralPath \$literalDeployDir'
fi
! grep -Eq 'md5sum|change-this-secret|Get-Random' \
    "$repo_dir/deploy-peta.sh" \
    "$repo_dir/deploy-peta-linux.sh" \
    "$repo_dir/deploy-peta.ps1"

echo "release security smoke passed"
