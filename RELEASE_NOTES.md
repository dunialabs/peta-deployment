# Peta 1.3.0

Peta 1.3.0 is a coordinated release of Core, Console, Auth, and the unified deployment scripts. The three Peta images use the shared tag `1.3.0` on `linux/amd64` and `linux/arm64`.

## Highlights

- Added the reviewed MCP `2026-07-28` stateless HTTP compatibility path while preserving legacy MCP clients and downstream servers.
- Added modern HTTP/SSE request correlation, bounded downstream responses, capability negotiation and preservation, subscription isolation, reconnect handling, and stricter protocol failure behavior.
- Hardened OAuth, public URL handling, token masking, and persistent log redaction across gateway paths.
- Updated Console create/edit flows and API handlers for protocol selection, remote launch configuration, and unknown MCP capability round trips.
- Made the Console image reproducible from a clean checkout while preserving the published image's offline tool-template fallback.
- Added HubSpot and Canva providers to Peta Auth. The Auth runtime payload is unchanged from the existing production image and is promoted to the coordinated `1.3.0` tag after health and architecture verification.
- Changed the unified macOS, Linux, and Windows installers to pin Core, Console, and Auth to one `PETA_VERSION` instead of mutable `latest` tags.

## MCP compatibility scope

- Modern MCP `2026-07-28` ingress and modern HTTP downstream probing remain controlled by `MCP_2026_ENABLED` and `MCP_2026_DOWNSTREAM_ENABLED`; both can be disabled for rollback.
- Modern downstream mode is HTTP-only. Stdio and explicit SSE downstream transports continue through the legacy-compatible SDK path.
- Persistent modern downstream subscriptions, downstream progress/cancellation bridging, and standard reverse requests are not advertised in this release. The legacy MCP paths remain available for those existing gateway flows.
- Peta Core keeps the legacy `@modelcontextprotocol/sdk` 1.x client path and implements the modern stateless boundary in its local adapter; an SDK 2.x migration is not part of `1.3.0`.

## Install

Run the installer for the host platform. The default version is `1.3.0`:

```sh
./deploy-peta.sh
```

Linux hosts that need Docker service management can use `./deploy-peta-linux.sh`; Windows hosts can use `./deploy-peta.ps1`.

## Update

In an existing generated deployment directory, keep the database and Auth volumes, set `PETA_VERSION=1.3.0` in `.env`, then run:

```sh
docker compose pull
docker compose up -d
docker compose ps
```

Normal container startup applies the repositories' existing database migration flow. This release does not add a new Core or Console schema migration beyond the already published migration history.

## Verify

- Core: `curl -fsS http://localhost:3002/health`
- Console: `curl -fsS http://localhost:3000/`
- Auth: `docker compose ps peta-auth` should report healthy; `/healthz` is internal to the Compose network.

## Rollback

Set `PETA_VERSION` in `.env` to the previously deployed release, then run `docker compose pull && docker compose up -d`. Do not use `docker compose down -v`; named PostgreSQL and Auth volumes must be preserved.
