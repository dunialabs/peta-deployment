# Peta 1.3.0

> Pre-publication notes: do not install or update to `1.3.0` until the Core,
> Console, and Auth `1.3.0` manifests are published for both `linux/amd64` and
> `linux/arm64`.

Peta 1.3.0 is a coordinated release of Core, Console, Auth, and the unified deployment scripts. The three Peta images will use the shared tag `1.3.0` on `linux/amd64` and `linux/arm64`.

## Highlights

- Added the reviewed MCP `2026-07-28` stateless HTTP compatibility path while preserving legacy MCP clients and downstream servers.
- Added modern HTTP/SSE request correlation, bounded downstream responses, capability negotiation and preservation, subscription isolation, reconnect handling, and stricter protocol failure behavior.
- Hardened OAuth, public URL handling, token masking, and persistent log redaction across gateway paths.
- Updated Console create/edit flows and API handlers for protocol selection, remote launch configuration, and unknown MCP capability round trips.
- Made the Console image reproducible from a clean checkout while preserving the published image's offline tool-template fallback.
- Removed repository TLS credentials from the current Console source and excluded local key/certificate files from Git and Docker build contexts. The private key remains recoverable from Git history, so revoke and replace the exposed credential even if it was not knowingly deployed. Public Git tags, GitHub Releases, and `latest` promotion remain blocked until revocation/rotation and replacement-deployment evidence is recorded.
- Patched production-reachable denial-of-service dependencies in Core Socket.IO/ZIP handling and Console Next.js, HTTP, and YAML processing.
- Added HubSpot and Canva providers to Peta Auth and moved the release build to Go 1.26.6. The existing Auth image must not be promoted to `1.3.0`; the current source must be rebuilt and pass multi-architecture health, binary vulnerability, and digest verification.
- Changed the unified macOS, Linux, and Windows installers to pin Core and Console with `PETA_VERSION` and Auth with `PETA_AUTH_VERSION`; both default to `1.3.0` for a coordinated installation.
- Changed installer secret generation to use operating-system cryptographic randomness and restrict generated `.env` files to the current user.
- When `PETA_AUTH_AUTOSTART=true`, installers now require a pre-provisioned raw 32-byte `./secrets/peta_auth_master_key` and non-empty encrypted `./secrets/peta_auth_client_secrets.json`. They enforce current-user-only access, keep both values out of `.env` and output, and mount them only into `peta-auth`.
- Peta does not expose or retain previous credential values as a recovery history. Keep protected prior secret material and rotation records outside Peta when your rollback policy requires them.

## MCP compatibility scope

- Modern MCP `2026-07-28` ingress and modern HTTP downstream probing remain controlled by `MCP_2026_ENABLED` and `MCP_2026_DOWNSTREAM_ENABLED`; both can be disabled for rollback.
- Modern downstream mode is HTTP-only. Stdio and explicit SSE downstream transports continue through the legacy-compatible SDK path.
- Persistent modern downstream subscriptions, downstream progress/cancellation bridging, and standard reverse requests are not advertised in this release. The legacy MCP paths remain available for those existing gateway flows.
- Peta Core keeps the legacy `@modelcontextprotocol/sdk` 1.x client path and implements the modern stateless boundary in its local adapter; an SDK 2.x migration is not part of `1.3.0`.

## Install

After all three `1.3.0` image manifests are published, run the installer for the host platform:

```sh
./deploy-peta.sh
```

Linux hosts that need Docker service management can use `./deploy-peta-linux.sh`; Windows hosts can use `./deploy-peta.ps1`.

If you enable Peta Auth, create `${DEPLOY_DIR:-./peta-deployment}/secrets/` and provision `peta_auth_master_key` (raw 32 bytes) and `peta_auth_client_secrets.json` (non-empty encrypted client-secrets JSON) there before running the installer. The installer treats this secrets-only directory as a new deployment and fails before generating Compose configuration unless the directory and both files are protected for the current user. Peta Auth validates and decrypts the JSON before listening. The installer never creates, copies, prints, or stores either value in `.env`.

## Update

After publication, in an existing generated deployment directory, keep the database and Auth volumes, set `PETA_VERSION=1.3.0` and `PETA_AUTH_VERSION=1.3.0` in `.env`, then run:

```sh
docker compose pull
docker compose up -d
docker compose ps
```

Normal container startup applies the repositories' existing database migration flow. This release does not add a new Core or Console schema migration beyond the already published migration history. Keep the same Auth secret pair and `peta-auth-core-data` volume during updates; changing either can make existing Auth data unreadable.

## Verify

- Core: `curl -fsS http://localhost:3002/health`
- Console: `curl -fsS http://localhost:3000/`
- Auth: `docker compose ps peta-auth` should report healthy; `/healthz` is internal to the Compose network.

## Rollback

To roll Core and Console back while retaining the compatible Auth release, pin the generated `.env` as follows, then run `docker compose pull && docker compose up -d`:

```dotenv
PETA_VERSION=PREVIOUS_CORE_CONSOLE_VERSION
PETA_AUTH_VERSION=1.3.0
```

Preserve the same Auth secret pair and Auth volume. Images from before runtime-secret support rely on embedded keys and are not compatible with this provisioning contract. Do not use `docker compose down -v`; named PostgreSQL and Auth volumes must be preserved.
