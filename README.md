# Peta Deployment

This installer generates a Docker Compose deployment for the matching Peta release.

See [RELEASE_NOTES.md](./RELEASE_NOTES.md) for the current release changes and upgrade notes.

## Images

- `petaio/peta-core:${PETA_VERSION}`: MCP gateway and control plane.
- `petaio/peta-console:${PETA_VERSION}`: web console.
- `petaio/peta-auth:${PETA_VERSION}`: optional internal authentication service.

The default release is `1.3.0`. All Peta images use the same `PETA_VERSION` value.

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

Set `PETA_VERSION` before running an installer to deploy another published release:

```sh
PETA_VERSION=1.3.0 ./deploy-peta.sh
```

```powershell
$env:PETA_VERSION = '1.3.0'; .\deploy-peta.ps1
```

The generated `.env` records `PETA_VERSION` and is restricted to the current OS user because it contains database and application secrets.

## Update and rollback

From the generated deployment directory, preserve the named volumes and update only the image version:

```sh
# Edit .env and set PETA_VERSION to the target release, then:
docker compose pull
docker compose up -d
```

For rollback, set `PETA_VERSION` in `.env` to the previously working release and run the same two commands. Do not run `docker compose down -v` or remove the `postgres_peta_*` / `peta-auth-core-data` volumes unless intentionally discarding data.

## Health checks

- Core: `http://localhost:${BACKEND_PORT:-3002}/health`
- Console: `http://localhost:${CONSOLE_PORT:-3000}/`
- Auth: `http://peta-auth:7788/healthz` from the Compose network only; use `docker compose ps` for its container health on the host.
