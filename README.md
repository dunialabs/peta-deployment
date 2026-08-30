# Peta Deployment

> Peta `1.3.0` is published for `linux/amd64` and `linux/arm64`. Production
> deployments should use the versioned tags; this release does not publish
> `latest`.

This installer generates a Docker Compose deployment for the matching Peta release.

See [RELEASE_NOTES.md](./RELEASE_NOTES.md) for the current release changes and upgrade notes.

## Images

- `bcdunia/peta-core:${PETA_VERSION}`: MCP gateway and control plane.
- `bcdunia/peta-console:${PETA_VERSION}`: web console.
- `bcdunia/peta-auth:${PETA_AUTH_VERSION}`: optional internal authentication service.

The current release is `1.3.0`. New installers default both `PETA_VERSION` and
`PETA_AUTH_VERSION` to `1.3.0`; Core and Console use `PETA_VERSION`, while Auth
uses `PETA_AUTH_VERSION` so a Core/Console rollback does not downgrade Auth.

## Install

Run the installer for the target platform and select the services to deploy:

```sh
./deploy-peta.sh
# Linux hosts with Docker service management:
./deploy-peta-linux.sh
```

```powershell
.\deploy-peta.ps1
```

To select an explicit coordinated version, set both image versions before running an installer:

```sh
PETA_VERSION='X.Y.Z' PETA_AUTH_VERSION='X.Y.Z' ./deploy-peta.sh
```

```powershell
$env:PETA_VERSION = 'X.Y.Z'; $env:PETA_AUTH_VERSION = 'X.Y.Z'; .\deploy-peta.ps1
```

The generated `.env` records `PETA_VERSION` and `PETA_AUTH_VERSION` and is restricted to the current OS user because it contains database and application secrets.

Before running the installer with Peta Auth enabled, create the protected
`$DEPLOY_DIR/secrets` directory (`DEPLOY_DIR` defaults to `./peta-deployment`) and provision:

- `$DEPLOY_DIR/secrets/peta_auth_master_key`: raw 32-byte key, owner-only readable.
- `$DEPLOY_DIR/secrets/peta_auth_client_secrets.json`: non-empty encrypted client-secrets JSON, owner-only readable.

The installers treat a directory containing only these pre-provisioned secrets
as a new deployment. They fail closed when either file is absent, the master key
is not exactly 32 raw bytes, the encrypted JSON file is empty, or the `secrets`
directory or either file is not restricted to the current user (Windows applies the same ACL pattern used for
`.env`). Peta Auth validates and decrypts the JSON before listening. The
installers never generate, copy, print, or put either value in `.env`; Compose
mounts both only into `peta-auth` at runtime.

## Update and rollback

From the generated deployment directory, preserve the named volumes and update only the image version:

```sh
# For a coordinated update, set both PETA_VERSION and PETA_AUTH_VERSION.
# Keep PETA_AUTH_VERSION unchanged for a Core/Console-only update, then:
docker compose pull
docker compose up -d
```

For a normal coordinated install, both values default to `1.3.0`. The verified
rollback target in the `bcdunia` namespace is Core and Console `1.2.0`. To use
it while keeping Auth at its compatible release, set the generated `.env` as
follows and run the same two commands:

```dotenv
PETA_VERSION=1.2.0
PETA_AUTH_VERSION=1.3.0
```

Keep the same Auth secret pair and `peta-auth-core-data` volume across install, update, and rollback; changing either can make existing Auth data unreadable. Do not run `docker compose down -v` or remove the `postgres_peta_*` / `peta-auth-core-data` volumes unless intentionally discarding data. Auth images released before runtime-secret support use embedded keys and are not compatible with this provisioning contract.

## Health checks

- Core: `http://localhost:${BACKEND_PORT:-3002}/health`
- Console: `http://localhost:${CONSOLE_PORT:-3000}/`
- Auth: `http://peta-auth:7788/healthz` from the Compose network only; use `docker compose ps` for its container health on the host.
